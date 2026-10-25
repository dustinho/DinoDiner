-- Dino Diner: feed a baby T-Rex the number of strawberries it asks for.
-- Playdate front end: input, audio and drawing.  Rules live in game.lua.

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
    bowl = loadImage("images/bowl_empty"),
    bowlFront = loadImage("images/bowl_front"),
    berry = loadImage("images/strawberry"),
    berrySmall = loadImage("images/strawberry_small"),
    berryOutline = loadImage("images/strawberry_outline"),
    heart = loadImage("images/heart"),
    heartBig = loadImage("images/heart_big"),
    trex = {},
    num = {},
}
for _, pose in ipairs({ "idle", "blink", "excited", "curious", "chomp", "chew", "happy" }) do
    img.trex[pose] = loadImage("images/trex_" .. pose)
end
for n = 1, 10 do
    img.num[n] = loadImage("images/numbers/num_" .. n)
end

local SOUND_NAMES = { "title", "instructions", "hint_empty", "hint_more", "hint_less",
    "hint_ready", "yum_1", "yum_2", "yum_3", "again",
    "pop", "remove", "chomp", "chew", "cheer", "whoosh", "bump" }
for n = 1, 10 do
    SOUND_NAMES[#SOUND_NAMES + 1] = "count_" .. n
    SOUND_NAMES[#SOUND_NAMES + 1] = "request_" .. n
end

local samples = {}
for _, name in ipairs(SOUND_NAMES) do
    samples[name] = snd.sampleplayer.new("sounds/" .. name)
    assert(samples[name], "missing sound: " .. name)
end

local currentVoice = nil
local audio = {}
function audio:sfx(name)
    samples[name]:play()
end
function audio:voice(name)
    if currentVoice then currentVoice:stop() end
    currentVoice = samples[name]
    currentVoice:play()
end
function audio:voicePlaying()
    return currentVoice ~= nil and currentVoice:isPlaying()
end

local game = Game.new(audio)

if pd.ui.crankIndicator.start then
    pd.ui.crankIndicator:start()   -- required before SDK 2.1, harmless after
end

---------------------------------------------------------------- drawing
local function drawAButton(cx, cy, r)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(cx, cy, r)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned("*A*", cx + 1, cy - 8, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
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

local function drawBubble(contentImg, number)
    local b = Layout.bubble
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRoundRect(b.x, b.y, b.w, b.h, 8)
    gfx.fillTriangle(b.x + 14, b.y + b.h - 3, b.x + 34, b.y + b.h - 3, b.x - 6, b.y + b.h + 16)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(3)
    gfx.drawRoundRect(b.x, b.y, b.w, b.h, 8)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(b.x + 16, b.y + b.h - 3, 17, 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(b.x + 14, b.y + b.h - 1, b.x - 6, b.y + b.h + 16)
    gfx.drawLine(b.x + 34, b.y + b.h - 1, b.x - 6, b.y + b.h + 16)
    gfx.setLineWidth(1)
    local cw, ch = contentImg:getSize()
    contentImg:draw(b.x + 14, b.y + (b.h - ch) // 2)
    if number then
        local n = img.num[number]
        local nw, nh = n:getSize()
        local left = b.x + 14 + cw
        n:draw(left + (b.x + b.w - left - nw) // 2, b.y + (b.h - nh) // 2)
    end
end

local POP_OFFSET <const> = { -7, -5, -3, -1 }

local function drawBowl(g)
    local bx, by = Layout.bowl.x, Layout.bowl.y
    img.bowl:draw(bx, by)
    for i = 1, g.count do
        local x, y = Layout.berryPos(i)
        local popped = g.pops[i]
        if g.state == "play" and popped and g.frame - popped < #POP_OFFSET then
            y = y + POP_OFFSET[g.frame - popped + 1]
        end
        img.berry:draw(x, y)
    end
    local _, bh = img.bowl:getSize()
    local _, fh = img.bowlFront:getSize()
    img.bowlFront:draw(bx, by + bh - fh)
    -- a small "poof" where a berry was taken out
    gfx.setColor(gfx.kColorBlack)
    for _, p in ipairs(g.poofs) do
        local x, y = Layout.berryPos(p.i)
        x, y = x + 12, y + 12
        local r1, r2 = 4 + p.t, 7 + p.t * 1.5
        for k = 0, 5 do
            local a = k * math.pi / 3
            gfx.drawLine(x + math.cos(a) * r1, y + math.sin(a) * r1,
                x + math.cos(a) * r2, y + math.sin(a) * r2)
        end
    end
end

local function drawSlots(g)
    for i = 1, math.max(g.target, g.count) do
        if not g:slotFlashOff(i) then
            local x, y = Layout.slotPos(i)
            if i <= g.count and i > g.target then
                -- extra berries beyond the request show up dark
                gfx.setImageDrawMode(gfx.kDrawModeInverted)
                img.berrySmall:draw(x, y)
                gfx.setImageDrawMode(gfx.kDrawModeCopy)
            elseif i <= g.count then
                img.berrySmall:draw(x, y)
            else
                img.berryOutline:draw(x, y)
            end
        end
    end
end

local function drawPlayHints(g)
    local cx, cy = 370, 108
    if g.state ~= "play" then return end
    if g.count == g.target and g.pending == 0 then
        drawAButton(cx, cy, 12 + (g.frame // 8) % 2)
    elseif g.idle > 45 or g.count == 0 then
        drawCrankIcon(cx, cy, g.frame, g.count > g.target and -1 or 1)
    end
end

local function drawDino(g)
    local y = Layout.dino.y
    if g.state == "celebrate" then
        y = y - math.floor(math.abs(math.sin(g.celebrateFrames * 0.25)) * 6)
    end
    img.trex[g:pose()]:draw(Layout.dino.x, y)
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
        drawBubble(img.heartBig, g.target)
    else
        drawBubble(img.berry, g.target)
    end
    if g.state == "play" then drawSlots(g) end
    drawBowl(g)
    drawDino(g)
    local x, y = g:flyingPos()
    if x then img.berry:draw(x, y) end
    if g.state == "celebrate" then
        drawHearts(g)
        if g.celebrateFrames > 15 then
            drawAButton(372, 104, 12 + (g.frame // 8) % 2)
        end
    end
    drawPlayHints(g)
    if g.state == "play" and pd.isCrankDocked() then
        pd.ui.crankIndicator:draw()
    end
end

local function drawTitle(g)
    img.title:draw(0, 0)
    local bob = math.floor(math.sin(g.frame * 0.2) * 2 + 0.5)
    drawAButton(212, 159 + bob, 12)
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
        right = pd.buttonJustPressed(pd.kButtonRight),
    })
    if game.state == "title" then
        drawTitle(game)
    else
        drawPlay(game)
    end
end
