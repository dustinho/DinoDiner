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

local function newGame(seq)
    local audio = fakeAudio()
    local i = 0
    local rnd = function(lo, hi)
        if seq then i = i + 1; return seq[(i - 1) % #seq + 1] end
        return math.random(lo, hi)
    end
    return Game.new(audio, rnd), audio
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
        g.firstRound = false
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
    g.firstRound = false
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
    g.firstRound = false
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
    g.firstRound = false
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
    g.firstRound = false
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
    g.firstRound = false
    g:startRound(3)
    step(g, { ticks = 2 })
    run(g, 12)
    eq(audio.voices[#audio.voices], "request_3", "request still playing")
    run(g, 30)
    eq(audio.voices[#audio.voices], "count_2")
end)

test("too few -> 'need more', recover, half point", function()
    local g, audio = newGame()
    g.firstRound = false
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
    g.firstRound = false
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
    g.firstRound = false
    g:startRound(2)
    step(g, { a = true })
    eq(audio.voices[#audio.voices], "hint_empty")
    eq(g.mistakes, 0)
end)

test("idle child gets a gentle reminder, at most three", function()
    local g, audio = newGame()
    g.firstRound = false
    g:startRound(2)
    run(g, 2000)
    local n = 0
    for _, v in ipairs(audio.voices) do if v == "hint_empty" then n = n + 1 end end
    eq(n, 3)
end)

test("celebration waits for A; A during feeding is ignored", function()
    local g = newGame()
    g.firstRound = false
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
    local g = newGame({ 2, 1, 3, 2, 1, 3 })
    step(g, { a = true })
    local seen = {}
    for _ = 1, 14 do
        seen[#seen + 1] = g.target
        feedCorrect(g)
    end
    -- stage 1: 1,2,3 (3 points) -> stage 2: 4,5 then one random (3 points)
    -- -> stage 3: 6,7,8,9,10
    eq(table.concat(seen, ",", 1, 5), "1,2,3,4,5")
    check(seen[6] >= 1 and seen[6] <= 5, "random within stage 2")
    eq(table.concat(seen, ",", 7, 11), "6,7,8,9,10")
    eq(g.stage, 3)
end)

test("random targets never repeat back to back", function()
    local g = newGame({ 3, 3, 3, 2 })
    g.stage = 1
    g.introduced = { [1] = true, [2] = true, [3] = true }
    g.lastTarget = 3
    eq(g:pickTarget(), 2)
end)

test("berry layout stays inside the bowl", function()
    for i = 1, 10 do
        local x, y = Layout.berryPos(i)
        check(x >= Layout.bowl.x + 8 and x + 30 <= Layout.bowl.x + 173 - 8, "berry x " .. i)
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
    check(#mock.played > 0, "sounds played")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
