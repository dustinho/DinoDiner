-- Minimal Playdate API mock for running source/main.lua under plain Lua 5.4.
-- It verifies assets exist, records draw calls per frame (for
-- tools/render_preview.py) and lets tests script button/crank input.
-- This is NOT the Playdate Simulator: it cannot catch rendering or
-- performance differences of the real SDK.

local M = {}
M.source = "source/"
M.ops = {}            -- draw calls of the current frame
M.input = {}          -- buttons "just pressed" this frame
M.ticks = 0           -- crank ticks returned this frame
M.docked = false
M.played = {}         -- log of sample names started
M.playing = {}        -- name -> frames left
M.frame = 0

local function rec(...) M.ops[#M.ops + 1] = { ... } end

local function pngSize(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read(24)
    f:close()
    local function be32(i)
        local a, b, c, d = data:byte(i, i + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return be32(17), be32(21)
end

local function wavFrames(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    -- 16-bit mono 22050 Hz: bytes / 2 / 22050 seconds, at 30 fps
    return math.max(1, math.floor((size - 44) / 2 / 22050 * 30 + 0.5))
end

---------------------------------------------------------------- graphics
local gfx = {
    kColorBlack = 0, kColorWhite = 1, kColorClear = 2, kColorXOR = 3,
    kDrawModeCopy = "copy", kDrawModeFillWhite = "fillWhite",
    kDrawModeFillBlack = "fillBlack", kDrawModeInverted = "inverted",
}
local Image = {}
Image.__index = Image
function Image:draw(x, y) rec("image", self.path, x, y) end
function Image:getSize() return self.width, self.height end

gfx.image = {}
function gfx.image.new(path)
    local w, h = pngSize(M.source .. path .. ".png")
    if not w then return nil end
    return setmetatable({ path = path, width = w, height = h }, Image)
end
for _, name in ipairs({ "setColor", "setLineWidth", "setImageDrawMode", "fillRect",
    "fillRoundRect", "drawRoundRect", "fillTriangle", "drawLine", "fillCircleAtPoint",
    "drawCircleAtPoint", "drawTextAligned", "clear" }) do
    gfx[name] = function(...) rec(name, ...) end
end

---------------------------------------------------------------- sound
local Sample = {}
Sample.__index = Sample
function Sample:play()
    M.played[#M.played + 1] = self.name
    M.playing[self.name] = self.frames
end
function Sample:stop() M.playing[self.name] = nil end
function Sample:isPlaying() return (M.playing[self.name] or 0) > 0 end

---------------------------------------------------------------- playdate
playdate = {
    graphics = gfx,
    display = { setRefreshRate = function() end },
    sound = { sampleplayer = { new = function(path)
        local frames = wavFrames(M.source .. path .. ".wav")
        if not frames then return nil end
        return setmetatable({ name = path:gsub("^sounds/", ""), frames = frames }, Sample)
    end } },
    ui = { crankIndicator = { draw = function() rec("crankIndicator") end } },
    kButtonA = "a", kButtonB = "b", kButtonUp = "up", kButtonDown = "down",
    kButtonLeft = "left", kButtonRight = "right",
    getSecondsSinceEpoch = function() return 12345 end,
    getCrankTicks = function() local t = M.ticks; M.ticks = 0; return t end,
    isCrankDocked = function() return M.docked end,
    buttonJustPressed = function(b) return M.input[b] == true end,
}
kTextAlignment = { left = 0, center = 1, right = 2 }

function import(name)
    if name:match("^CoreLibs/") then return end
    dofile(M.source .. name .. ".lua")
end

-- Advance one frame with the given input, e.g. { a = true, ticks = 3 }.
function M.step(input)
    input = input or {}
    M.input = input
    M.ticks = input.ticks or 0
    M.ops = {}
    M.frame = M.frame + 1
    for name, left in pairs(M.playing) do
        M.playing[name] = left - 1
        if left <= 1 then M.playing[name] = nil end
    end
    playdate.update()
end

function M.load()
    dofile(M.source .. "main.lua")
end

-- Write the current frame's draw calls in a simple line format.
function M.dump(path)
    local f = assert(io.open(path, "w"))
    for _, op in ipairs(M.ops) do
        local parts = {}
        for i, v in ipairs(op) do parts[i] = tostring(v) end
        f:write(table.concat(parts, "\t"), "\n")
    end
    f:close()
end

return M
