-- Dino Diner: feed a baby T-Rex (and friends) the strawberries they ask for.
-- Playdate front end: input, audio, saving and drawing.  Rules live in game.lua.

import "CoreLibs/graphics"
import "CoreLibs/crank"
import "CoreLibs/ui"
import "game"

local pd <const> = playdate
local gfx <const> = pd.graphics
local snd <const> = pd.sound

pd.display.setRefreshRate(30)
math.randomseed(pd.getSecondsSinceEpoch())

---------------------------------------------------------------- assets
local function loadImage(path)
    local img = gfx.image.new(path)
    assert(img, "missing image: " .. path)
    return img
end

local img = {
    title = loadImage("images/title"),
    bg = loadImage("images/play_bg"),
    berry = loadImage("images/strawberry"),
    berryMini = loadImage("images/strawberry_mini"),
    heart = loadImage("images/heart"),
    heartBig = loadImage("images/heart_big"),
    aButton = loadImage("images/a_button"),
    aButtonBig = loadImage("images/a_button_big"),
    times = loadImage("images/numbers/times"),
    trex = {},
    num = {},
    numSmall = {},
    friends = {},
}
for _, pose in ipairs({ "idle", "blink", "excited", "curious", "chomp", "chew", "happy" }) do
    img.trex[pose] = loadImage("images/trex_" .. pose)
end
for n = 0, 25 do
    img.num[n] = loadImage("images/numbers/num_" .. n)
end
for n = 1, 5 do
    img.numSmall[n] = loadImage("images/numbers/num_s_" .. n)
end
for _, name in ipairs({ "trex", table.unpack(Game.FRIENDS) }) do
    img.friends[name] = {}
    for _, pose in ipairs({ "idle", "chomp", "happy" }) do
        img.friends[name][pose] = loadImage("images/friends/" .. name .. "_" .. pose)
    end
end

-- Effects are preloaded; voice clips (there are many) load when first used.
local EFFECTS = { "pop", "remove", "chomp", "chew", "cheer", "whoosh", "bump" }
local samples = {}
local function sample(name)
    local s = samples[name]
    if not s then
        s = snd.sampleplayer.new("sounds/" .. name)
        assert(s, "missing sound: " .. name)
        samples[name] = s
    end
    return s
end
for _, name in ipairs(EFFECTS) do sample(name) end

local currentVoice = nil
local audio = {}
function audio:sfx(name)
    sample(name):play()
end
function audio:voice(name)
    if currentVoice then currentVoice:stop() end
    currentVoice = sample(name)
    currentVoice:play()
end
function audio:voicePlaying()
    return currentVoice ~= nil and currentVoice:isPlaying()
end

-- Chosen game and levels survive restarts.
local store = {}
function store:load() return pd.datastore.read("settings") end
function store:save(t) pd.datastore.write(t, "settings") end

local game = Game.new(audio, nil, store)

if pd.ui.crankIndicator.start then
    pd.ui.crankIndicator:start()   -- required before SDK 2.1, harmless after
end

---------------------------------------------------------------- drawing helpers
local function drawCentered(image, cx, cy)
    local w, h = image:getSize()
    image:draw(cx - w // 2, cy - h // 2)
end

-- Pre-rendered so the "A" is centred to the pixel; `big` = pulse frame.
local function drawAButton(cx, cy, big)
    drawCentered(big and img.aButtonBig or img.aButton, cx, cy)
end

-- A little crank: circle, turning arm and knob.  dir = 1 / -1.
local function drawCrankIcon(cx, cy, frame, dir)
    local a = dir * frame * 0.25
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx, cy, 17)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(3)
    gfx.drawCircleAtPoint(cx, cy, 15)
    local ex, ey = cx + math.cos(a) * 11, cy + math.sin(a) * 11
    gfx.drawLine(cx, cy, ex, ey)
    gfx.fillCircleAtPoint(ex, ey, 4)
    gfx.fillCircleAtPoint(cx, cy, 3)
    gfx.setLineWidth(1)
end

-- Speech bubble frame.  `invert` flips it to black: the "look at the
-- number" blink after a "need more" answer.
local function drawBubbleFrame(b, invert)
    local tipX, tipY = b.tip[1], b.tip[2]
    -- the tail leaves the bottom edge on the side nearest the tip
    local mid = math.max(b.x + 24, math.min(b.x + b.w - 24, tipX))
    local l, r = mid - 11, mid + 11
    local fill = invert and gfx.kColorBlack or gfx.kColorWhite
    gfx.setColor(fill)
    gfx.fillRoundRect(b.x, b.y, b.w, b.h, 10)
    gfx.fillTriangle(l, b.y + b.h - 3, r, b.y + b.h - 3, tipX, tipY)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(3)
    gfx.drawRoundRect(b.x, b.y, b.w, b.h, 10)
    gfx.setColor(fill)
    gfx.fillRect(l + 2, b.y + b.h - 3, r - l - 3, 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(l, b.y + b.h - 1, tipX, tipY)
    gfx.drawLine(r, b.y + b.h - 1, tipX, tipY)
    gfx.setLineWidth(1)
end

local function drawInk(image, cx, cy, invert)
    if invert then gfx.setImageDrawMode(gfx.kDrawModeFillWhite) end
    drawCentered(image, cx, cy)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- Counting: [berry] N.   Multiplying: [dino] G  x  [berry] E.
local function drawBubble(g, icon, invert)
    local b = g:layout().bubble
    drawBubbleFrame(b, invert)
    local cy = b.y + b.h // 2
    if g.mode == "count" then
        local cw, ch = icon:getSize()
        icon:draw(b.x + 12, cy - ch // 2)
        local left = b.x + 12 + cw
        drawInk(img.num[g.target], (left + b.x + b.w) // 2, cy, invert)
    else
        local x = b.x + 6
        drawCentered(img.friends.trex.idle, x + 24, cy)
        drawInk(img.numSmall[g.groups], x + 62, cy, invert)
        drawInk(img.times, x + 84, cy, invert)
        drawCentered(icon, x + 112, cy)
        drawInk(img.numSmall[g.each], x + 146, cy, invert)
    end
end

-- Running total: how many berries are on the tray right now.  It hops
-- when the total changes and turns black when it matches the request.
local function drawTotal(g)
    local t = g:layout().total
    local n, matched = g:shownTotal()
    local y = t.y
    if g.changed and g.frame - g.changed < 4 then y = y - (4 - (g.frame - g.changed)) end
    gfx.setColor(matched and gfx.kColorBlack or gfx.kColorWhite)
    gfx.fillRoundRect(t.x, y, t.w, t.h, 8)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(3)
    gfx.drawRoundRect(t.x, y, t.w, t.h, 8)
    gfx.setLineWidth(1)
    local mw, mh = img.berryMini:getSize()
    if matched then gfx.setImageDrawMode(gfx.kDrawModeInverted) end
    img.berryMini:draw(t.x + 7, y + (t.h - mh) // 2)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    local left = t.x + 7 + mw
    drawInk(img.num[math.min(n, 25)], (left + t.x + t.w) // 2, y + t.h // 2, matched)
end

---------------------------------------------------------------- grid
local POP_OFFSET <const> = { -7, -5, -3, -1 }

-- Dotted outline of one grid cell (inset so neighbours don't share edges).
local function drawCell(x, y)
    gfx.setColor(gfx.kColorBlack)
    gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
    gfx.drawRoundRect(x + 1, y + 1, 32, 33, 5)
    gfx.setColor(gfx.kColorBlack)
end

local function drawMat(x, y, w, h, lineWidth)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRoundRect(x, y, w, h, 8)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(lineWidth)
    gfx.drawRoundRect(x, y, w, h, 8)
    gfx.setLineWidth(1)
end

-- Grid tray: counting shows a 2x5 grid; multiplying one row per dino,
-- as many cells wide as each dino wants.
local function drawTray(g)
    local L = g:layout().grid
    if g.mode == "count" then
        drawMat(L.x - 6, L.y - 6, 5 * L.dx + 12, 2 * L.dy + 12, 3)
        for r = 0, 1 do
            for c = 0, 4 do drawCell(L.x + c * L.dx, L.y + r * L.dy) end
        end
    else
        for r = 1, g.groups do
            local y = L.y + (r - 1) * L.dy
            drawMat(L.x - 3, y - 1, g.each * L.dx + 6, L.dy, 2)
            for c = 0, g.each - 1 do drawCell(L.x + c * L.dx, y) end
        end
    end
end

local function drawBerries(g)
    for i = 1, g.count do
        local x, y = g:cellPos(i)
        local popped = g.pops[i]
        if g.state == "play" and popped and g.frame - popped < #POP_OFFSET then
            y = y + POP_OFFSET[g.frame - popped + 1]
        end
        if i > g.target and g.state == "play" then
            -- extra berries beyond the request show up dark (and blink
            -- after a "too many" answer)
            if not (g.hint == "less" and g:hintBlinkOff()) then
                gfx.setImageDrawMode(gfx.kDrawModeInverted)
                img.berry:draw(x, y)
                gfx.setImageDrawMode(gfx.kDrawModeCopy)
            end
        else
            img.berry:draw(x, y)
        end
    end
    -- a small "poof" where a berry was taken out
    gfx.setColor(gfx.kColorBlack)
    for _, p in ipairs(g.poofs) do
        local x, y = g:cellPos(p.i)
        x, y = x + 15, y + 16
        local r1, r2 = 4 + p.t, 7 + p.t * 1.5
        for k = 0, 5 do
            local a = k * math.pi / 3
            gfx.drawLine(x + math.cos(a) * r1, y + math.sin(a) * r1,
                x + math.cos(a) * r2, y + math.sin(a) * r2)
        end
    end
end

-- One dino at the start of each row; they hop when their row is full.
local function drawFriends(g)
    if g.mode ~= "multiply" then return end
    for r = 1, g.groups do
        local x, y = g:portraitPos(r)
        local pose = g:friendPose(r)
        if pose == "happy" and g.state ~= "feeding" then
            y = y - math.floor(math.abs(math.sin((g.frame + r * 7) * 0.3)) * 3)
        end
        img.friends[g.friends[r]][pose]:draw(x, y)
    end
end

---------------------------------------------------------------- scene
local function drawPlayHints(g)
    local p = g:layout().prompt
    if g.state ~= "play" then return end
    if g.count == g.target and g.pending == 0 then
        drawAButton(p.x, p.y, (g.frame // 8) % 2 == 1)
    elseif g.idle > 45 or g.count == 0 then
        drawCrankIcon(p.x, p.y, g.frame, g.count > g.target and -1 or 1)
    end
end

local function drawDino(g)
    local d = g:layout().dino
    local y = d.y
    if g.state == "celebrate" then
        y = y - math.floor(math.abs(math.sin(g.celebrateFrames * 0.25)) * 6)
    end
    img.trex[g:pose()]:draw(d.x, y)
end

local function drawHearts(g)
    local f = g.celebrateFrames
    for k = 0, 4 do
        local phase = (f * 3 // 2 + k * 19) % 80
        local x = 40 + k * 24 + math.floor(math.sin((f + k * 13) * 0.15) * 4 + 0.5)
        local y = 110 - phase
        if phase < 70 then img.heart:draw(x, y) end
    end
end

local function drawPlay(g)
    img.bg:draw(0, 0)
    if g.state == "celebrate" then
        drawBubble(g, img.heartBig)
    else
        local blink = (g.hint == "more" or g.hint == "empty") and g:hintBlinkOff()
        drawBubble(g, img.berry, blink)
    end
    drawTray(g)
    drawBerries(g)
    drawTotal(g)
    drawDino(g)
    drawFriends(g)
    for _, f in ipairs(g:flyingBerries()) do
        if f.small then
            img.berryMini:draw(f.x + 7, f.y + 8)
        else
            img.berry:draw(f.x, f.y)
        end
    end
    if g.state == "celebrate" then
        drawHearts(g)
        if g.celebrateFrames > 15 then
            local p = g:layout().prompt
            drawAButton(p.x, p.y, (g.frame // 8) % 2 == 1)
        end
    end
    drawPlayHints(g)
    if g.state == "play" and pd.isCrankDocked() then
        pd.ui.crankIndicator:draw()
    end
end

-- Title: game choice (left/right) and level (up/down) under PLAY.
local function drawTitle(g)
    img.title:draw(0, 0)
    local bob = math.floor(math.sin(g.frame * 0.2) * 2 + 0.5)
    drawAButton(212, 159 + bob, false)
    local cx, y = 282, 180
    drawMat(cx - 62, y, 124, 40, 2)
    -- arrows hint that left/right changes the game
    gfx.fillTriangle(cx - 56, y + 11, cx - 50, y + 6, cx - 50, y + 16)
    gfx.fillTriangle(cx + 56, y + 11, cx + 50, y + 6, cx + 50, y + 16)
    gfx.drawTextAligned(g.mode == "count" and "*Counting*" or "*Multiplying*",
        cx, y + 3, kTextAlignment.center)
    -- level pips: filled up to the current level
    for i = 1, 3 do
        local px = cx - 20 + (i - 1) * 20
        if i <= g:level() then
            gfx.fillCircleAtPoint(px, y + 30, 5)
        else
            gfx.drawCircleAtPoint(px, y + 30, 5)
        end
    end
end

---------------------------------------------------------------- main loop
function pd.update()
    local ticks = pd.getCrankTicks(10)
    game:update({
        ticks = ticks,
        a = pd.buttonJustPressed(pd.kButtonA),
        b = pd.buttonJustPressed(pd.kButtonB),
        up = pd.buttonJustPressed(pd.kButtonUp),
        down = pd.buttonJustPressed(pd.kButtonDown),
        left = pd.buttonJustPressed(pd.kButtonLeft),
        right = pd.buttonJustPressed(pd.kButtonRight),
    })
    if game.state == "title" then
        drawTitle(game)
    else
        drawPlay(game)
    end
end
