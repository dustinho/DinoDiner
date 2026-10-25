-- Dino Diner regression tests.  Run from the repository root:
--   lua5.4 tools/test_game.lua [preview_dir]
-- Part 1 drives game.lua directly with a fake audio object.
-- Part 2 runs main.lua against tools/playdate_mock.lua (asset loading,
-- drawing code paths) and, if preview_dir is given, dumps draw calls for
-- tools/render_preview.py.

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("ok   " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. "\n     " .. tostring(err))
    end
end
local function eq(a, b, msg)
    if a ~= b then
        error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2)
    end
end
local function check(c, msg) if not c then error(msg or "check failed", 2) end end

dofile("source/game.lua")

---------------------------------------------------------------- fake audio
local function fakeAudio()
    local a = { log = {}, voices = {}, sfxs = {}, left = 0 }
    function a:sfx(n) self.log[#self.log + 1] = n; self.sfxs[#self.sfxs + 1] = n end
    function a:voice(n)
        self.log[#self.log + 1] = n
        self.voices[#self.voices + 1] = n
        self.left = 20
    end
    function a:voicePlaying() return self.left > 0 end
    function a:tick() if self.left > 0 then self.left = self.left - 1 end end
    return a
end

local function memoryStore(initial)
    local st = { data = initial }
    function st:load() return self.data end
    function st:save(t) self.data = t end
    return st
end

local function newGame(seq, store)
    local audio = fakeAudio()
    local i = 0
    local rnd = function(lo, hi)
        if seq then i = i + 1; return seq[(i - 1) % #seq + 1] end
        return math.random(lo, hi)
    end
    return Game.new(audio, rnd, store), audio
end

local function step(g, input)
    g.audio:tick()
    g:update(input or {})
end

local function run(g, n, input)
    for _ = 1, n do step(g, input) end
end

local function runUntil(g, pred, limit)
    for _ = 1, limit or 2000 do
        if pred() then return true end
        step(g)
    end
    return pred()
end

local function contains(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

local function feedCorrect(g)
    step(g, { ticks = g.target })
    step(g, { a = true })
    check(runUntil(g, function() return g.state == "celebrate" end), "never celebrated")
    run(g, 20)
    step(g, { a = true })
end

---------------------------------------------------------------- logic tests
test("title -> instructions then first request", function()
    local g, audio = newGame()
    eq(g.state, "title")
    eq(audio.voices[1], "title")
    step(g, { a = true })
    eq(g.state, "play")
    eq(g.target, 1)
    eq(audio.voices[#audio.voices], "instructions")
    run(g, 25)
    eq(audio.voices[#audio.voices], "request_1", "request follows instructions")
end)

test("every quantity 1-10 can be fed and is eaten one by one", function()
    for n = 1, 10 do
        local g, audio = newGame()
        g.taught.count = true
        g:startRound(n)
        step(g, { ticks = n })
        step(g, { a = true })
        check(g.state == "play" or g.state == "feeding")
        local prev = g.count
        local maxCount = g.count
        check(runUntil(g, function()
            check(math.abs(g.count - prev) <= 1, "count jumped")
            prev = g.count
            maxCount = math.max(maxCount, g.count)
            return g.state == "feeding"
        end), "never started feeding for " .. n)
        eq(maxCount, n, "bowl count")
        local start = #audio.voices
        check(runUntil(g, function() return g.state == "celebrate" end), "no celebration " .. n)
        eq(g.eaten, n, "eaten")
        eq(g.count, 0, "bowl emptied")
        local counted = {}
        for i = start + 1, #audio.voices do
            if audio.voices[i]:match("^count_") then counted[#counted + 1] = audio.voices[i] end
        end
        eq(#counted, n, "counted aloud while eating")
        for i = 1, n do eq(counted[i], "count_" .. i) end
        check(contains(audio.sfxs, "chomp"))
    end
end)

test("fast crank adds berries one at a time and stops at 10", function()
    local g, audio = newGame()
    g.taught.count = true
    g:startRound(4)
    step(g, { ticks = 25 })
    local prev, pops = g.count, 0
    for _ = 1, 60 do
        step(g)
        check(g.count - prev <= 1, "more than one berry per frame")
        prev = g.count
    end
    eq(g.count, 10)
    eq(g.pending, 0)
    for _, s in ipairs(audio.sfxs) do if s == "pop" then pops = pops + 1 end end
    eq(pops, 10, "one pop per berry")
    check(contains(audio.sfxs, "bump") or true)
    step(g, { ticks = 5 })
    eq(g.pending, 0, "no queue past 10")
    check(contains(audio.sfxs, "bump"), "gentle bump at the limit")
end)

test("removing below zero is impossible", function()
    local g = newGame()
    g.taught.count = true
    g:startRound(2)
    step(g, { ticks = -3 })
    eq(g.pending, 0)
    step(g, { b = true })
    step(g, { down = true })
    run(g, 10)
    eq(g.count, 0)
end)

test("feed pressed while crank steps are queued waits for them", function()
    local g, audio = newGame()
    g.taught.count = true
    g:startRound(6)
    step(g, { ticks = 6, a = true })
    eq(g.state, "play")
    check(g.count < 6)
    check(runUntil(g, function() return g.state == "feeding" end, 60))
    check(not contains(audio.voices, "hint_more"), "no premature 'need more'")
    eq(g.mistakes, 0)
end)

test("count is spoken once, after turning settles", function()
    local g, audio = newGame()
    g.taught.count = true
    g:startRound(5)
    run(g, 30) -- request finishes
    local before = #audio.voices
    step(g, { ticks = 5 })
    run(g, 60)
    local spoken = {}
    for i = before + 1, #audio.voices do spoken[#spoken + 1] = audio.voices[i] end
    eq(spoken[1], "count_5")
    for _, v in ipairs(spoken) do
        check(v == "count_5" or v == "hint_ready", "unexpected voice " .. v)
    end
end)

test("count waits for the request voice instead of interrupting", function()
    local g, audio = newGame()
    g.taught.count = true
    g:startRound(3)
    step(g, { ticks = 2 })
    run(g, 12)
    eq(audio.voices[#audio.voices], "request_3", "request still playing")
    run(g, 30)
    eq(audio.voices[#audio.voices], "count_2")
end)

test("too few -> 'need more', recover, half point", function()
    local g, audio = newGame()
    g.taught.count = true
    g:startRound(3)
    step(g, { ticks = 2 })
    run(g, 10)
    step(g, { a = true })
    eq(g.state, "play")
    eq(audio.voices[#audio.voices], "hint_more")
    eq(g.hint, "more")
    eq(g:pose(), "curious")
    eq(g.mistakes, 1)
    step(g, { up = true })
    run(g, 5)
    eq(g.count, 3)
    eq(g:pose(), "excited")
    step(g, { a = true })
    eq(g.state, "feeding")
    check(runUntil(g, function() return g.state == "celebrate" end))
    run(g, 20)
    step(g, { a = true })
    eq(g.points, 0.5)
end)

test("too many -> 'too many', crank back", function()
    local g, audio = newGame()
    g.taught.count = true
    g:startRound(2)
    step(g, { ticks = 4 })
    run(g, 15)
    step(g, { a = true })
    eq(audio.voices[#audio.voices], "hint_less")
    eq(g.hint, "less")
    step(g, { ticks = -2 })
    run(g, 10)
    eq(g.count, 2)
    step(g, { a = true })
    eq(g.state, "feeding")
end)

test("empty bowl -> spoken hint, not a mistake", function()
    local g, audio = newGame()
    g.taught.count = true
    g:startRound(2)
    step(g, { a = true })
    eq(audio.voices[#audio.voices], "hint_empty")
    eq(g.mistakes, 0)
end)

test("idle child gets a gentle reminder, at most three", function()
    local g, audio = newGame()
    g.taught.count = true
    g:startRound(2)
    run(g, 2000)
    local n = 0
    for _, v in ipairs(audio.voices) do if v == "hint_empty" then n = n + 1 end end
    eq(n, 3)
end)

test("celebration waits for A; A during feeding is ignored", function()
    local g = newGame()
    g.taught.count = true
    g:startRound(2)
    step(g, { ticks = 2 })
    run(g, 8)
    step(g, { a = true })
    eq(g.state, "feeding")
    step(g, { a = true })
    eq(g.state, "feeding")
    check(runUntil(g, function() return g.state == "celebrate" end))
    run(g, 600)
    eq(g.state, "celebrate", "no auto-advance")
    step(g, { a = true })
    eq(g.state, "play")
end)

test("progression: 1,2,3 then 4,5 then 6..10 introduced in order", function()
    local store = memoryStore()
    local g = newGame({ 2, 1, 3, 2, 1, 3 }, store)
    step(g, { a = true })
    local seen = {}
    for _ = 1, 14 do
        seen[#seen + 1] = g.target
        feedCorrect(g)
    end
    -- level 1: 1,2,3 (3 points) -> level 2: 4,5 then one random (3 points)
    -- -> level 3: 6,7,8,9,10
    eq(table.concat(seen, ",", 1, 5), "1,2,3,4,5")
    check(seen[6] >= 1 and seen[6] <= 5, "random within level 2")
    eq(table.concat(seen, ",", 7, 11), "6,7,8,9,10")
    eq(g.levels.count, 3)
    eq(store.data.levels.count, 3, "unlocked level is saved")
end)

test("random targets never repeat back to back", function()
    local g = newGame({ 3, 3, 3, 2 })
    g.introduced = { [1] = true, [2] = true, [3] = true }
    g.lastTarget = 3
    eq(g:pickCount(), 2)
end)

test("counting grid: 2 rows of 5, inside the tray", function()
    local g = newGame()
    g.taught.count = true
    g:startRound(10)
    local L = Layout.count.grid
    for i = 1, 10 do
        local x, y = g:cellPos(i)
        eq(x, L.x + ((i - 1) % 5) * L.dx + 2, "column " .. i)
        eq(y, L.y + ((i - 1) // 5) * L.dy + 2, "row " .. i)
        check(x >= 0 and x + 30 <= 400 and y + 32 <= 240, "on screen " .. i)
    end
end)

---------------------------------------------------------------- title / settings
test("title: left/right picks the game, up/down the level, both saved", function()
    local store = memoryStore()
    local g, audio = newGame(nil, store)
    eq(g.mode, "count")
    step(g, { right = true })
    eq(g.mode, "multiply")
    eq(audio.voices[#audio.voices], "mode_multiply")
    run(g, 25)
    eq(audio.voices[#audio.voices], "level_1", "level announced after the game")
    step(g, { up = true })
    eq(g:level(), 2)
    eq(audio.voices[#audio.voices], "level_2")
    step(g, { up = true })
    step(g, { up = true })
    eq(g:level(), 3, "capped at 3")
    check(contains(audio.sfxs, "bump"))
    eq(store.data.mode, "multiply")
    eq(store.data.levels.multiply, 3)
    eq(store.data.levels.count, 1, "other game keeps its level")
    step(g, { left = true })
    eq(g.mode, "count")
end)

test("saved settings are restored; junk is ignored", function()
    local g = newGame(nil, memoryStore({ mode = "multiply", levels = { count = 3, multiply = 2 } }))
    eq(g.mode, "multiply")
    eq(g.levels.count, 3)
    eq(g.levels.multiply, 2)
    local g2 = newGame(nil, memoryStore({ mode = "chess", levels = { count = 9, multiply = "x" } }))
    eq(g2.mode, "count")
    eq(g2.levels.count, 1)
    eq(g2.levels.multiply, 1)
    local g3 = newGame(nil, memoryStore("garbage"))
    eq(g3.mode, "count")
end)

---------------------------------------------------------------- multiplying
local function multiplyGame(seq)
    local g, audio = newGame(seq)
    g.mode = "multiply"
    g.taught.multiply = true
    return g, audio
end

test("multiplying: first round explains, then invites friends and asks", function()
    local g, audio = newGame()
    g.mode = "multiply"
    g:startRound(3, 2)
    eq(audio.voices[#audio.voices], "share_intro")
    eq(table.concat(g.voiceQueue, ","), "invite_2,each_2")
    eq(g.target, 6)
    eq(#g.friends, 3)
    eq(g.friends[1], "trex")
    check(g.friends[2] ~= g.friends[3], "different friends")
end)

test("multiplying: every groups x each from 2x1 to 5x5 can be fed", function()
    for groups = 2, 5 do
        for each = 1, 5 do
            local g, audio = multiplyGame()
            g:startRound(groups, each)
            step(g, { ticks = groups * each })
            step(g, { a = true })
            check(runUntil(g, function() return g.state == "feeding" end), "no feeding")
            local start = #audio.voices
            check(runUntil(g, function() return g.state == "celebrate" end), "no celebration")
            eq(g.eaten, groups * each)
            -- skip-counting: one count per row, in steps of `each`
            local counted = {}
            for i = start + 1, #audio.voices do
                if audio.voices[i]:match("^count_") then counted[#counted + 1] = audio.voices[i] end
            end
            eq(#counted, groups, "one count per row " .. groups .. "x" .. each)
            for r = 1, groups do eq(counted[r], "count_" .. r * each) end
            eq(audio.voices[#audio.voices], "fact_" .. groups .. "_" .. each)
        end
    end
end)

test("multiplying: berries fill row by row, one row per dino", function()
    local g = multiplyGame()
    g:startRound(3, 4)
    local L = Layout.multiply.grid
    for i = 1, 12 do
        local x, y = g:cellPos(i)
        eq(y, L.y + ((i - 1) // 4) * L.dy + 2, "row of berry " .. i)
        eq(x, L.x + ((i - 1) % 4) * L.dx + 2, "column of berry " .. i)
    end
    step(g, { ticks = 4 })
    run(g, 20)
    eq(g:friendPose(1), "happy", "first dino's row is full")
    eq(g:friendPose(2), "idle")
end)

test("multiplying: rows are eaten bottom-up, each by its own dino", function()
    local g = multiplyGame()
    g:startRound(3, 2)
    step(g, { ticks = 6 })
    step(g, { a = true })
    check(runUntil(g, function() return #g.flying > 0 end), "berries fly")
    -- first flight: the bottom row's berries, to the bottom dino's mouth
    local mx, my = g:mouthPos(3)
    for _, f in ipairs(g.flying) do
        eq(f.row, 3, "bottom row first")
        eq(f.tx, mx)
        eq(f.ty, my)
        local _, y = g:cellPos(5)
        eq(f.y, y, "berries come from the bottom row")
    end
    eq(g.count, 4, "rows 1-2 still on the tray")
    eq(g:friendPose(3), "chomp")
    eq(g:friendPose(1), "idle")
    check(runUntil(g, function() return g.rowsEaten == 1 end))
    eq(g:friendPose(3), "happy")
    check(runUntil(g, function() return #g.flying > 0 end))
    eq(g.flying[1].row, 2, "then the middle row")
end)

test("multiplying: one extra row allowed, never past five rows or 25", function()
    local g = multiplyGame()
    g:startRound(2, 3)
    eq(g.maxCount, 9)
    g:startRound(5, 5)
    eq(g.maxCount, 25)
    g:startRound(4, 5)
    eq(g.maxCount, 25)
    g:startRound(5, 2)
    eq(g.maxCount, 10)
end)

test("multiplying: too few repeats how many each dino wants", function()
    local g, audio = multiplyGame()
    g:startRound(2, 3)
    step(g, { ticks = 4 })
    run(g, 20)
    step(g, { a = true })
    eq(g.hint, "more")
    eq(audio.voices[#audio.voices], "hint_more")
    eq(g.voiceQueue[1], "each_3")
end)

test("multiplying: levels stay in range", function()
    for level = 1, 3 do
        local g = multiplyGame()
        g.levels.multiply = level
        local lv = Game.LEVELS.multiply[level]
        for _ = 1, 50 do
            g:startRound()
            check(g.groups >= lv.groups[1] and g.groups <= lv.groups[2], "groups")
            check(g.each >= lv.each[1] and g.each <= lv.each[2], "each")
        end
    end
end)

test("running total badge: tray count, eaten count, then the whole amount", function()
    local g = newGame()
    g.taught.count = true
    g:startRound(3)
    step(g, { ticks = 2 })
    run(g, 10)
    local n, matched = g:shownTotal()
    eq(n, 2)
    eq(matched, false)
    step(g, { up = true })
    run(g, 5)
    n, matched = g:shownTotal()
    eq(n, 3)
    eq(matched, true, "black when it matches")
    step(g, { a = true })
    check(runUntil(g, function() return g.state == "celebrate" end))
    n, matched = g:shownTotal()
    eq(n, 3)
    for _, mode in ipairs(Game.MODES) do
        local t = Layout[mode].total
        check(t.x >= 0 and t.x + t.w <= 400 and t.y + t.h <= 240, mode .. " badge on screen")
        local b = Layout[mode].bubble
        check(t.x >= b.x + b.w + 8 or t.x + t.w <= b.x - 8 or t.y >= b.y + b.h + 8,
            mode .. " badge clear of bubble")
        local p = Layout[mode].prompt
        check(p.x - 17 >= b.x + b.w and p.x + 17 <= t.x, mode .. " prompt between bubble and badge")
    end
end)

test("multiplying layout: 5x5 grid, extra row and dinos fit on screen", function()
    local g = multiplyGame()
    g:startRound(4, 5)
    for i = 1, g.maxCount do
        local x, y = g:cellPos(i)
        check(x >= 0 and x + 30 <= 400 and y >= 0 and y + 32 <= 240, "berry " .. i)
    end
    g.state = "feeding"
    for r = 1, 4 do
        local x, y = g:portraitPos(r)
        check(x >= 0 and x + 48 <= Layout.multiply.grid.x - 2 and y + 40 <= 240, "dino " .. r)
        local mx, my = g:mouthPos(r)
        check(mx > x and my > y, "mouth inside sprite " .. r)
    end
end)

---------------------------------------------------------------- main.lua smoke test
local previewDir = arg and arg[1]

test("main.lua runs every state against the Playdate mock", function()
    local mock = dofile("tools/playdate_mock.lua")
    mock.load()
    local function snap(name)
        if previewDir then mock.dump(previewDir .. "/" .. name .. ".txt") end
    end
    local function frames(n, input) for _ = 1, n do mock.step(input) end end
    frames(10)
    snap("01_title")
    mock.step({ a = true })
    frames(40)
    snap("02_play_empty")
    -- force a known target so previews are deterministic
    local g = nil
    -- main.lua keeps the game local; reach it through Game.new's metatable
    -- by re-running a round on the one visible via the registry hook below
    g = Game._last
    check(g, "game instance visible")
    g:startRound(4)
    frames(100)
    snap("03_play_request_4")
    mock.step({ ticks = 2 })
    frames(2)
    snap("04_play_pop")
    frames(40)
    snap("05_play_two")
    mock.step({ a = true })
    frames(3)
    snap("06_hint_more")
    mock.step({ ticks = 2 })
    frames(30)
    snap("07_play_correct")
    mock.step({ a = true })
    frames(25)
    snap("08_feeding")
    frames(16)
    snap("08b_feeding_chomp")
    local ok = false
    for _ = 1, 400 do
        mock.step()
        if g.state == "celebrate" then ok = true break end
    end
    check(ok, "reached celebration")
    frames(30)
    snap("09_celebrate")
    mock.step({ a = true })
    g:startRound(10)
    mock.step({ ticks = 10 })
    frames(60)
    snap("10_play_ten")
    g:startRound(7)
    mock.step({ ticks = 9 })
    frames(40)
    mock.step({ a = true })
    frames(5)
    snap("11_hint_less")
    mock.docked = true
    frames(2)
    snap("12_crank_docked")
    mock.docked = false
    -- multiplying game
    g.state = "title"
    mock.step({ right = true })
    frames(5)
    snap("13_title_multiply")
    g.taught.multiply = true
    g:startRound(3, 4)
    frames(4)
    snap("14_friends_arrive")
    frames(60)
    mock.step({ ticks = 6 })
    frames(40)
    snap("15_multiply_half")
    mock.step({ ticks = 6 })
    frames(40)
    snap("16_multiply_full")
    mock.step({ a = true })
    frames(40)
    snap("17_multiply_feeding")
    ok = false
    for _ = 1, 400 do
        mock.step()
        if g.state == "celebrate" then ok = true break end
    end
    check(ok, "multiplying reached celebration")
    frames(30)
    snap("18_multiply_celebrate")
    g:startRound(5, 5)
    mock.step({ ticks = 25 })
    frames(120)
    snap("19_multiply_5x5")
    g:startRound(2, 3)
    mock.step({ ticks = 9 })
    frames(60)
    mock.step({ a = true })
    frames(5)
    snap("20_multiply_too_many")
    check(mock.saved.settings and mock.saved.settings.mode == "multiply", "settings saved")
    check(#mock.played > 0, "sounds played")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
