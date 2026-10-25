-- Dino Diner game logic.
--
-- Pure Lua: no Playdate API calls, so tools/test_game.lua can drive it
-- frame by frame.  main.lua feeds it input once per frame and draws the
-- resulting state.  Sound goes through an injected `audio` object with
--   audio:sfx(name)          play a short effect
--   audio:voice(name)        start a voice clip (stopping any current one)
--   audio:voicePlaying()     true while a voice clip is still playing
-- and settings persist through an optional `store` object with
--   store:load() -> table or nil,   store:save(table)
--
-- Two games:
--   "count"     the T-Rex asks for 1-10 strawberries, shown in a 2x5 grid
--   "multiply"  the T-Rex invites friends; every dino wants the same number,
--               so the berries form a grid: one row per dino

Game = {}
Game.__index = Game

Game.STEP_FRAMES = 3        -- frames between queued crank steps (10 berries/s)
Game.SETTLE_FRAMES = 9      -- quiet frames before the count is spoken
Game.FLY_FRAMES = 12        -- frames for a berry to reach a mouth
Game.EAT_INTERVAL = 17      -- frames between berries (counting game)
Game.ROW_INTERVAL = 28      -- frames between rows (multiplying game)
Game.CHEW_FRAMES = 36       -- extra chewing once the grid is empty
Game.CURIOUS_FRAMES = 75    -- how long the "hmm?" face / hint blink lasts
Game.NUDGE_FRAMES = 180     -- idle frames before a gentle spoken reminder
Game.ARRIVE_FRAMES = 14     -- frames for a friend to walk in
Game.POINTS_TO_ADVANCE = 3

Game.MODES = { "count", "multiply" }

-- Levels per game.  Counting: targets 1..max, with `intro` numbers
-- presented in order the first time.  Multiplying: `groups` dinos (the
-- T-Rex plus friends) each wanting `each` strawberries.
Game.LEVELS = {
    count = {
        { max = 3,  intro = { 1, 2, 3 } },
        { max = 5,  intro = { 4, 5 } },
        { max = 10, intro = { 6, 7, 8, 9, 10 } },
    },
    multiply = {
        { groups = { 2, 2 }, each = { 1, 3 } },
        { groups = { 2, 3 }, each = { 1, 4 } },
        { groups = { 2, 5 }, each = { 1, 5 } },
    },
}

Game.FRIENDS = { "triceratops", "stegosaurus", "brachiosaurus", "ankylosaurus" }

-- Screen layout shared by logic (berry positions, flight paths) and drawing.
Layout = {
    berrySize = { w = 30, h = 32 },
    count = {
        dino = { x = 2, y = 92 },
        mouth = { x = 136, y = 152 },
        bubble = { x = 196, y = 10, w = 164, h = 92, tip = { 202, 120 } },
        prompt = { x = 283, y = 124 },          -- crank / A-button nudge icon
        grid = { x = 198, y = 150, cols = 5, dx = 34, dy = 36 },
    },
    multiply = {
        dino = { x = -26, y = 92 },
        mouth = { x = 110, y = 152 },
        bubble = { x = 186, y = 4, w = 176, h = 50, tip = { 158, 74 } },
        prompt = { x = 150, y = 34 },
        grid = { x = 226, y = 64, dx = 34, dy = 35 },
        portraitX = 178,
    },
    -- mouth position inside each 46x40 friend sprite
    friendMouth = {
        trex = { 38, 22 }, triceratops = { 41, 28 }, stegosaurus = { 40, 31 },
        brachiosaurus = { 38, 12 }, ankylosaurus = { 40, 33 },
    },
}

function Game.new(audio, random, store)
    local g = setmetatable({}, Game)
    g.audio = audio
    g.random = random or math.random
    g.store = store
    g.state = "title"
    g.frame = 0
    g.mode = "count"
    g.levels = { count = 1, multiply = 1 }
    local saved = store and store:load()
    if type(saved) == "table" then
        if saved.mode == "count" or saved.mode == "multiply" then g.mode = saved.mode end
        if type(saved.levels) == "table" then
            for _, m in ipairs(Game.MODES) do
                local n = tonumber(saved.levels[m])
                if n and n >= 1 and n <= 3 then g.levels[m] = math.floor(n) end
            end
        end
    end
    g.points = 0
    g.introduced = {}
    g.taught = {}
    g.voiceQueue = {}
    g.target, g.groups, g.each = 0, 1, 0
    g.count = 0
    g.pending = 0
    g.pops = {}
    g.poofs = {}
    g.flying = {}
    g.friends = {}
    g.audio:voice("title")
    Game._last = g   -- lets the test harness reach the running game
    return g
end

function Game:save()
    if self.store then
        self.store:save({ mode = self.mode,
            levels = { count = self.levels.count, multiply = self.levels.multiply } })
    end
end

function Game:level() return self.levels[self.mode] end
function Game:layout() return Layout[self.mode] end

---------------------------------------------------------------- voice
function Game:say(name)
    self.voiceQueue = {}
    self.audio:voice(name)
end

function Game:sayNext(name)
    self.voiceQueue[#self.voiceQueue + 1] = name
end

function Game:voiceBusy()
    return self.audio:voicePlaying() or #self.voiceQueue > 0
end

function Game:updateVoice()
    if #self.voiceQueue > 0 and not self.audio:voicePlaying() then
        self.audio:voice(table.remove(self.voiceQueue, 1))
    end
end

-- The spoken request for the current round (also on D-pad right).
function Game:sayRequest(queue)
    local speak = queue and self.sayNext or self.say
    if self.mode == "count" then
        speak(self, "request_" .. self.target)
    else
        speak(self, "invite_" .. (self.groups - 1))
        self:sayNext("each_" .. self.each)
    end
end

---------------------------------------------------------------- grid
-- Top-left corner of berry i in the grid.  Counting fills a 2x5 grid;
-- multiplying fills one row per dino, `each` berries wide.
function Game:cellPos(i)
    local L = self:layout().grid
    local cols = self.mode == "count" and L.cols or self.each
    local row, col = (i - 1) // cols, (i - 1) % cols
    return L.x + col * L.dx + 2, L.y + row * L.dy + 2
end

-- Where berries for row r (multiplying) or the T-Rex (counting) go.
function Game:mouthPos(r)
    local L = self:layout()
    if self.mode == "count" then return L.mouth.x, L.mouth.y end
    local x, y = self:portraitPos(r)
    local m = Layout.friendMouth[self.friends[r]]
    return x + m[1], y + m[2]
end

function Game:portraitPos(r)
    local L = Layout.multiply
    local x = L.portraitX
    if self.state == "play" then   -- friends walk in from the right
        local t = self.roundFrames - (r - 1) * 6
        local left = Game.ARRIVE_FRAMES - math.max(0, math.min(Game.ARRIVE_FRAMES, t))
        x = x + left * 16
    end
    -- sprites are 40 tall, rows 35: feet sit on the row's bottom edge
    return x, L.grid.y + (r - 1) * L.grid.dy - 5
end

---------------------------------------------------------------- rounds
function Game:pickCount()
    local lv = Game.LEVELS.count[self:level()]
    for _, n in ipairs(lv.intro) do
        if not self.introduced[n] then
            self.introduced[n] = true
            return n
        end
    end
    local n
    repeat
        n = self.random(1, lv.max)
    until n ~= self.lastTarget or lv.max == 1
    return n
end

function Game:pickMultiply()
    local lv = Game.LEVELS.multiply[self:level()]
    local g, e
    for _ = 1, 20 do
        g = self.random(lv.groups[1], lv.groups[2])
        e = self.random(lv.each[1], lv.each[2])
        if g * e ~= self.lastTarget then break end
    end
    return g, e
end

-- startRound()             pick from the current level
-- startRound(n)            counting: ask for n
-- startRound(groups, each) multiplying
function Game:startRound(a, b)
    self.state = "play"
    if self.mode == "count" then
        self.groups, self.each = 1, a or self:pickCount()
        self.target = self.each
        self.maxCount = 10
        self.friends = {}
    else
        if a then self.groups, self.each = a, b else self.groups, self.each = self:pickMultiply() end
        self.target = self.groups * self.each
        self.maxCount = math.min(math.min(self.groups + 1, 5) * self.each, 25)
        -- the T-Rex's own row first, then a random set of friends
        local pool = { table.unpack(Game.FRIENDS) }
        self.friends = { "trex" }
        for _ = 2, self.groups do
            self.friends[#self.friends + 1] = table.remove(pool, self.random(1, #pool))
        end
    end
    self.lastTarget = self.target
    self.count = 0
    self.pending = 0
    self.stepTimer = 0
    self.feedQueued = false
    self.mistakes = 0
    self.curious = 0
    self.hint = nil
    self.idle = 0
    self.nudges = 0
    self.readyNudged = false
    self.settle = 0
    self.announced = 0
    self.roundFrames = 0
    self.pops, self.poofs, self.flying = {}, {}, {}
    self.blinkTimer = 60 + self.random(0, 60)
    if not self.taught[self.mode] then
        self.taught[self.mode] = true
        self:say(self.mode == "count" and "instructions" or "share_intro")
        self:sayRequest(true)
    else
        self:sayRequest()
    end
end

-- Apply round result to adaptive progression (called when the child
-- presses A after the celebration).
function Game:applyProgress()
    self.points = self.points + (self.mistakes == 0 and 1 or 0.5)
    if self.points >= Game.POINTS_TO_ADVANCE and self:level() < 3 then
        self.levels[self.mode] = self:level() + 1
        self.points = 0
        self:save()
    end
end

---------------------------------------------------------------- update
-- input = { ticks = crank ticks this frame, a, b, up, down, left, right = just pressed }
function Game:update(input)
    self.frame = self.frame + 1
    if self.state == "title" then
        self:updateTitle(input)
    elseif self.state == "play" then
        self.roundFrames = self.roundFrames + 1
        self:updatePlay(input)
    elseif self.state == "feeding" then
        self:updateFeeding()
    elseif self.state == "celebrate" then
        self.celebrateFrames = self.celebrateFrames + 1
        if input.a and self.celebrateFrames > 15 then
            self:applyProgress()
            self:startRound()
        end
    end
    self:updateVoice()
    for i = #self.poofs, 1, -1 do
        local p = self.poofs[i]
        p.t = p.t + 1
        if p.t > 8 then table.remove(self.poofs, i) end
    end
end

-- Title: left/right picks the game, up/down the level, A starts.
function Game:updateTitle(input)
    if input.left or input.right then
        self.mode = self.mode == "count" and "multiply" or "count"
        self.points = 0
        self:save()
        self.audio:sfx("pop")
        self:say("mode_" .. self.mode)
        self:sayNext("level_" .. self:level())
    elseif input.up or input.down then
        local n = math.max(1, math.min(3, self:level() + (input.up and 1 or -1)))
        if n ~= self:level() then
            self.levels[self.mode] = n
            self.points = 0
            self:save()
            self.audio:sfx("pop")
        else
            self.audio:sfx("bump")
        end
        self:say("level_" .. n)
    elseif input.a then
        self:startRound()
    end
end

function Game:queueSteps(n)
    if n == 0 then return end
    local want = self.pending + n
    local lo, hi = -self.count, self.maxCount - self.count
    if want > hi or want < lo then
        want = math.max(lo, math.min(hi, want))
        if want == self.pending and self.frame - (self.bumpFrame or -99) > 10 then
            self.bumpFrame = self.frame
            self.audio:sfx("bump")
        end
    end
    self.pending = want
end

function Game:updatePlay(input)
    local steps = input.ticks or 0
    if input.up then steps = steps + 1 end
    if input.down or input.b then steps = steps - 1 end
    if steps ~= 0 or input.a or input.right then
        self.idle = 0
    else
        self.idle = self.idle + 1
    end
    self:queueSteps(steps)
    if input.right then self:sayRequest() end
    if input.a then self.feedQueued = true end

    -- one berry at a time, however fast the crank turned
    if self.stepTimer > 0 then self.stepTimer = self.stepTimer - 1 end
    if self.pending ~= 0 and self.stepTimer == 0 then
        if self.pending > 0 then
            self.count = self.count + 1
            self.pending = self.pending - 1
            self.pops[self.count] = self.frame
            self.audio:sfx("pop")
        else
            self.poofs[#self.poofs + 1] = { i = self.count, t = 0 }
            self.pops[self.count] = nil
            self.count = self.count - 1
            self.pending = self.pending + 1
            self.audio:sfx("remove")
        end
        self.stepTimer = Game.STEP_FRAMES
        self.settle = 0
        self.readyNudged = false
        if self.hint then self.curious, self.hint = 0, nil end
    else
        self.settle = self.settle + 1
    end

    if self.pending == 0 and self.feedQueued then
        self.feedQueued = false
        self:evaluate()
        return
    end

    -- speak the total once turning stops and the voice is free
    if self.pending == 0 and self.settle >= Game.SETTLE_FRAMES
        and self.announced ~= self.count and not self:voiceBusy() then
        self.announced = self.count
        if self.count > 0 then self:say("count_" .. self.count) end
    end

    -- gentle reminders for a child who is stuck
    if not self:voiceBusy() and self.pending == 0 then
        if self.count == 0 and self.idle >= Game.NUDGE_FRAMES and self.nudges < 3 then
            self.nudges = self.nudges + 1
            self.idle = 0
            self:say("hint_empty")
        elseif self.count == self.target and self.idle >= Game.NUDGE_FRAMES / 2
            and not self.readyNudged then
            self.readyNudged = true
            self:say("hint_ready")
        end
    end

    if self.curious > 0 then
        self.curious = self.curious - 1
        if self.curious == 0 then self.hint = nil end
    end
    self.blinkTimer = self.blinkTimer - 1
    if self.blinkTimer < -4 then self.blinkTimer = 60 + self.random(0, 90) end
end

function Game:evaluate()
    self.announced = self.count     -- don't also speak the count
    if self.count == self.target then
        self:startFeeding()
        return
    end
    if self.count == 0 then
        self.hint = "empty"
        self:say("hint_empty")
    else
        self.mistakes = self.mistakes + 1
        if self.count < self.target then
            self.hint = "more"
            self:say("hint_more")
            if self.mode == "multiply" then self:sayNext("each_" .. self.each) end
        else
            self.hint = "less"
            self:say("hint_less")
        end
    end
    self.curious = Game.CURIOUS_FRAMES
end

---------------------------------------------------------------- feeding
function Game:startFeeding()
    self.state = "feeding"
    self.feedTimer = Game.EAT_INTERVAL - 4
    self.eaten = 0
    self.rowsEaten = 0
    self.rowsLaunched = 0
    self.flying = {}
    self.chewing = 0
    self.afterChew = nil
    self.voiceQueue = {}
end

local function launch(self, i, r)
    local x, y = self:cellPos(i)
    local tx, ty = self:mouthPos(r)
    self.flying[#self.flying + 1] = { x = x, y = y, tx = tx, ty = ty, t = 0, row = r }
end

function Game:updateFeeding()
    if self.chewing > 0 then self.chewing = self.chewing - 1 end
    -- advance berries in flight
    local landed = 0
    for i = #self.flying, 1, -1 do
        local f = self.flying[i]
        f.t = f.t + 1
        if f.t >= Game.FLY_FRAMES then
            table.remove(self.flying, i)
            landed = landed + 1
        end
    end
    if landed > 0 then
        self.eaten = self.eaten + landed
        self.chewing = 8
        self.audio:sfx("chomp")
        if self.mode == "multiply" then
            self.rowsEaten = self.rowsEaten + 1
        end
        self:say("count_" .. self.eaten)   -- count (or skip-count) along
    end
    -- launch the next berry (counting) or the next whole row (multiplying)
    self.feedTimer = self.feedTimer + 1
    if #self.flying == 0 and self.count > 0 then
        if self.mode == "count" and self.feedTimer >= Game.EAT_INTERVAL then
            launch(self, self.count, 1)
            self.count = self.count - 1
            self.feedTimer = 0
            self.audio:sfx("whoosh")
        elseif self.mode == "multiply" and self.feedTimer >= Game.ROW_INTERVAL then
            self.rowsLaunched = self.rowsLaunched + 1
            local r = self.rowsLaunched
            for i = (r - 1) * self.each + 1, r * self.each do launch(self, i, r) end
            self.count = self.count - self.each
            self.feedTimer = 0
            self.audio:sfx("whoosh")
        end
    end
    if #self.flying == 0 and self.count == 0 and self.eaten == self.target then
        self.afterChew = (self.afterChew or 0) + 1
        if self.afterChew % 10 == 1 then self.audio:sfx("chew") end
        if self.afterChew >= Game.CHEW_FRAMES then
            self.afterChew = nil
            self:startCelebrate()
        end
    end
end

-- Berries in flight: list of { x, y, t (0..1), small } on arcs into mouths.
-- Berries heading for a little friend shrink half way there.
function Game:flyingBerries()
    local out = {}
    local w, h = Layout.berrySize.w, Layout.berrySize.h
    for _, f in ipairs(self.flying) do
        local t = f.t / Game.FLY_FRAMES
        local ex, ey = f.tx - w // 2, f.ty - h // 2
        local lift = self.mode == "count" and 45 or 20
        local cx, cy = (f.x + ex) / 2, math.min(f.y, ey) - lift
        local u = 1 - t
        local x = u * u * f.x + 2 * u * t * cx + t * t * ex
        local y = u * u * f.y + 2 * u * t * cy + t * t * ey
        out[#out + 1] = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), t = t,
            small = self.mode == "multiply" and t > 0.5 }
    end
    return out
end

function Game:startCelebrate()
    self.state = "celebrate"
    self.celebrateFrames = 0
    self.audio:sfx("cheer")
    if self.mode == "count" then
        self:say("yum_" .. self.random(1, 3))
    else
        self:say("fact_" .. self.groups .. "_" .. self.each)
    end
    self:sayNext("again")
end

---------------------------------------------------------------- view helpers
-- Which T-Rex pose to show this frame.
function Game:pose()
    if self.state == "title" then return "excited" end
    if self.state == "feeding" then
        if self.mode == "multiply" then return "excited" end
        if self.chewing > 0 then
            return (self.chewing // 4) % 2 == 0 and "chew" or "chomp"
        end
        if self.afterChew then
            return (self.afterChew // 5) % 2 == 0 and "chew" or "chomp"
        end
        return "excited"
    end
    if self.state == "celebrate" then return "happy" end
    if self.curious > 0 then return "curious" end
    if self.count == self.target and self.pending == 0 then return "excited" end
    if self.blinkTimer < 0 then return "blink" end
    return "idle"
end

-- Pose of the dino owning row r (multiplying): smiles once its row is full.
function Game:friendPose(r)
    if self.state == "celebrate" then return "happy" end
    if self.state == "feeding" then
        if r <= self.rowsEaten then return "happy" end
        if r == self.rowsLaunched then return "chomp" end
        return "idle"
    end
    return self.count >= r * self.each and "happy" or "idle"
end

-- Gentle blinking after a wrong answer: true on the "off" half of a blink.
-- main.lua blinks the request bubble ("more"/"empty") or the extra
-- berries in the grid ("less").
function Game:hintBlinkOff()
    return self.curious > 0 and (self.frame // 6) % 2 == 1
end
