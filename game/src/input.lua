-- Turns gamepad buttons, the analog stick and keyboard keys into actions:
-- up down left right a b x y l1 r1 l2 r2 select start menu, plus
-- digit1..digit9 and erase from a PC keyboard. Directions, L2 and R2 repeat
-- while held.

local input = {}

local REPEAT_DELAY = 0.26
local REPEAT_RATE = 0.07
local STICK_THRESHOLD = 0.55
-- L2 and R2 arrive as trigger axes (0 to 1), even where they're plain buttons.
-- Two thresholds, so an analog trigger resting near one doesn't flicker.
local TRIGGER_PRESS, TRIGGER_RELEASE = 0.6, 0.4

local PAD = {
    dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
    a = "a", b = "b", x = "x", y = "y",
    leftshoulder = "l1", rightshoulder = "r1",
    back = "select", start = "start", guide = "menu",
}

local KEYS = {
    up = "up", down = "down", left = "left", right = "right",
    ["return"] = "a", kpenter = "a", space = "a", a = "a",
    backspace = "b", b = "b",
    x = "x", y = "y",
    q = "l1", e = "r1",
    pageup = "l2", pagedown = "r2",
    tab = "select", rshift = "select",
    escape = "start", p = "start",
}

local TRIGGERS = { triggerleft = "l2", triggerright = "r2" }

local REPEATS = { up = true, down = true, left = true, right = true, l2 = true, r2 = true }

local held = {}          -- [action] = { t = seconds held, next = next repeat time }
local stick = { x = nil, y = nil }
local triggers = {}      -- [axis] = true while pulled

input.handler = function() end

local function fire(action)
    input.handler(action)
end

local function press(action)
    if REPEATS[action] then
        held[action] = { t = 0, next = REPEAT_DELAY }
    end
    fire(action)
end

local function release(action)
    if REPEATS[action] then held[action] = nil end
end

function input.update(dt)
    for action, h in pairs(held) do
        h.t = h.t + dt
        while h.t >= h.next do
            h.next = h.next + REPEAT_RATE
            fire(action)
        end
    end
end

function input.reset()
    held = {}
end

function input.keypressed(key, isrepeat)
    if isrepeat then return end
    local digit = tonumber(key:match("^kp(%d)$") or key:match("^(%d)$") or "")
    if digit and digit >= 1 and digit <= 9 then
        fire("digit" .. digit)
        return
    end
    if key == "delete" or key == "0" or key == "kp0" then
        fire("erase")
        return
    end
    local action = KEYS[key]
    if action then press(action) end
end

function input.keyreleased(key)
    local action = KEYS[key]
    if action then release(action) end
end

function input.gamepadpressed(_, button)
    local action = PAD[button]
    if action then press(action) end
end

function input.gamepadreleased(_, button)
    local action = PAD[button]
    if action then release(action) end
end

function input.gamepadaxis(_, axis, value)
    local trigger = TRIGGERS[axis]
    if trigger then
        local down = triggers[axis]
        if not down and value >= TRIGGER_PRESS then
            triggers[axis] = true
            press(trigger)
        elseif down and value <= TRIGGER_RELEASE then
            triggers[axis] = nil
            release(trigger)
        end
    elseif axis == "leftx" or axis == "lefty" then
        local key = (axis == "leftx") and "x" or "y"
        local dir = nil
        if value <= -STICK_THRESHOLD then dir = (key == "x") and "left" or "up"
        elseif value >= STICK_THRESHOLD then dir = (key == "x") and "right" or "down" end
        if dir ~= stick[key] then
            if stick[key] then release(stick[key]) end
            stick[key] = dir
            if dir then press(dir) end
        end
    end
end

return input
