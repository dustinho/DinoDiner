-- Dino Diner game logic.
--
-- Pure Lua: no Playdate API calls, so tools/test_game.lua can drive it
-- frame by frame.  main.lua feeds it input once per frame and draws the
-- resulting state.  Sound goes through an injected `audio` object with
--   audio:sfx(name)          play a short effect
--   audio:voice(name)        start a voice clip (stopping any current one)
--   audio:voicePlaying()     true while a voice clip is still playing

Game = {}
Game.__index = Game

Game.MAX = 10
Game.STEP_FRAMES = 3        -- frames between queued crank steps (10 berries/s)
Game.SETTLE_FRAMES = 9      -- quiet frames before the count is spoken
Game.FLY_FRAMES = 12        -- frames for a berry to reach the mouth
Game.EAT_INTERVAL = 17      -- frames between berries leaving the bowl
Game.CHEW_FRAMES = 36       -- extra chewing once the bowl is empty
Game.CURIOUS_FRAMES = 75    -- how long the "hmm?" face / hint flash lasts
Game.NUDGE_FRAMES = 180     -- idle frames before a gentle spoken reminder
Game.POINTS_TO_ADVANCE = 3

-- Stage n allows targets 1..max; `intro` numbers are presented in order
-- the first time the stage is reached, then targets are random in range.
Game.STAGES = {
    { max = 3,  intro = { 1, 2, 3 } },
    { max = 5,  intro = { 4, 5 } },
    { max = 10, intro = { 6, 7, 8, 9, 10 } },
}

-- Screen layout shared by logic (berry flight paths) and drawing.
Layout = {
    dino = { x = 2, y = 92 },
    mouth = { x = 136, y = 152 },       -- where berries disappear
    bowl = { x = 194, y = 160 },
    bowlCenter = { x = 283, y = 178 },
    bubble = { x = 196, y = 10, w = 164, h = 92 },
    prompt = { x = 283, y = 124 },      -- crank / A-button nudge icon
    berrySize = { w = 30, h = 32 },
}

-- Top-left corner of berry i (1..10) inside the bowl.  1-5 sit in the
-- back row, 6-10 in a staggered front row.
local BACK_DX = { -59, -33, -7, 19, 45 }
local FRONT_DX = { -45, -19, 7, 33, 59 }
function Layout.berryPos(i)
    local c = Layout.bowlCenter
    local w, h = Layout.berrySize.w, Layout.berrySize.h
    if i <= 5 then
        return c.x + BACK_DX[i] - w // 2, 143
    end
    return c.x + FRONT_DX[i - 5] - w // 2, 158
end

function Game.new(audio, random)
    local g = setmetatable({}, Game)
    g.audio = audio
    g.random = random or math.random
    g.state = "title"
    g.frame = 0
    g.stage = 1
    g.points = 0
    g.introduced = {}
    g.lastTarget = nil
    g.firstRound = true
    g.voiceQueue = {}
    g.target = 0
    g.count = 0
    g.pending = 0
    g.pops = {}
    g.poofs = {}
    g.audio:voice("title")
    Game._last = g   -- lets the test harness reach the running game
    return g
end

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

---------------------------------------------------------------- targets
function Game:pickTarget()
    local stage = Game.STAGES[self.stage]
    for _, n in ipairs(stage.intro) do
        if not self.introduced[n] then
            self.introduced[n] = true
            return n
        end
    end
    local n
    repeat
        n = self.random(1, stage.max)
    until n ~= self.lastTarget or stage.max == 1
    return n
end

function Game:startRound(target)
    self.state = "play"
    self.target = target or self:pickTarget()
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
    self.pops, self.poofs = {}, {}
    self.blinkTimer = 60 + self.random(0, 60)
    if self.firstRound then
        self.firstRound = false
        self:say("instructions")
        self:sayNext("request_" .. self.target)
    else
        self:say("request_" .. self.target)
    end
end

-- Apply round result to adaptive progression (called when the child
-- presses A after the celebration).
function Game:applyProgress()
    self.points = self.points + (self.mistakes == 0 and 1 or 0.5)
    if self.points >= Game.POINTS_TO_ADVANCE and self.stage < #Game.STAGES then
        self.stage = self.stage + 1
        self.points = 0
    end
end

---------------------------------------------------------------- update
-- input = { ticks = crank ticks this frame, a, b, up, down, right = just pressed }
function Game:update(input)
    self.frame = self.frame + 1
    if self.state == "title" then
        if input.a then self:startRound() end
    elseif self.state == "play" then
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

function Game:queueSteps(n)
    if n == 0 then return end
    local want = self.pending + n
    local lo, hi = -self.count, Game.MAX - self.count
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
    if input.right then self:say("request_" .. self.target) end
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
    self.feedTimer = 0
    self.eaten = 0
    self.flying = nil
    self.chewing = 0
    self.feedFrames = 0
    self.voiceQueue = {}
end

function Game:updateFeeding()
    self.feedFrames = self.feedFrames + 1
    if self.chewing > 0 then self.chewing = self.chewing - 1 end
    local f = self.flying
    if f then
        f.t = f.t + 1
        if f.t >= Game.FLY_FRAMES then
            self.flying = nil
            self.eaten = self.eaten + 1
            self.chewing = 8
            self.audio:sfx("chomp")
            self:say("count_" .. self.eaten)   -- count along as he eats
        end
    end
    self.feedTimer = self.feedTimer + 1
    if not self.flying and self.count > 0 and self.feedTimer >= Game.EAT_INTERVAL then
        local x, y = Layout.berryPos(self.count)
        self.flying = { x = x, y = y, t = 0, i = self.count }
        self.count = self.count - 1
        self.feedTimer = 0
        self.audio:sfx("whoosh")
    end
    if not self.flying and self.count == 0 and self.eaten == self.target then
        self.afterChew = (self.afterChew or 0) + 1
        if self.afterChew % 10 == 1 then self.audio:sfx("chew") end
        if self.afterChew >= Game.CHEW_FRAMES then
            self.afterChew = nil
            self:startCelebrate()
        end
    end
end

-- Position of the flying berry (top-left), on an arc into the mouth.
function Game:flyingPos()
    local f = self.flying
    if not f then return nil end
    local t = f.t / Game.FLY_FRAMES
    local m = Layout.mouth
    local w, h = Layout.berrySize.w, Layout.berrySize.h
    local ex, ey = m.x - w // 2, m.y - h // 2
    local cx, cy = (f.x + ex) / 2, math.min(f.y, ey) - 45
    local u = 1 - t
    local x = u * u * f.x + 2 * u * t * cx + t * t * ex
    local y = u * u * f.y + 2 * u * t * cy + t * t * ey
    return math.floor(x + 0.5), math.floor(y + 0.5), t
end

function Game:startCelebrate()
    self.state = "celebrate"
    self.celebrateFrames = 0
    self.audio:sfx("cheer")
    self:say("yum_" .. self.random(1, 3))
    self:sayNext("again")
end

---------------------------------------------------------------- view helpers
-- Which T-Rex pose to show this frame.
function Game:pose()
    if self.state == "title" then return "excited" end
    if self.state == "feeding" then
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

-- Gentle blinking after a wrong answer: true on the "off" half of a blink.
-- main.lua blinks the requested number ("more"/"empty") or the extra
-- berries in the bowl ("less").
function Game:hintBlinkOff()
    return self.curious > 0 and (self.frame // 6) % 2 == 1
end
