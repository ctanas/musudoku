-- Run from the repository root:  luajit tests/test_game.lua
-- Puzzle state queries and the L2 / R2 controls.
package.path = "./game/?.lua;" .. package.path
local Game = require("src.game")
local input = require("src.input")

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

local P = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
local S = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"

local function digits(s)
    local out = {}
    for i = 1, 81 do out[i] = tonumber(s:sub(i, i)) end
    return out
end

local function newGame()
    return Game.new({ puzzle = digits(P), solution = digits(S) }, "easy")
end

local settings = { mistakes = false, autoclear = true }

-- nextEmpty ---------------------------------------------------------------------

local g = newGame()
check("next empty in the row", g:nextEmpty(1, 1) == 3, g:nextEmpty(1, 1))
check("skips givens", g:nextEmpty(4, 1) == 6, g:nextEmpty(4, 1))
check("previous empty", g:nextEmpty(5, -1) == 4, g:nextEmpty(5, -1))
check("wraps forward past the end", g:nextEmpty(81, 1) == 3, g:nextEmpty(81, 1))
check("wraps backward past the start", g:nextEmpty(1, -1) == 79, g:nextEmpty(1, -1))
g:toggleNote(3, 4)
check("cells with only notes count as empty", g:nextEmpty(1, 1) == 3, g:nextEmpty(1, 1))
g:enter(3, 4, settings)
check("filled cells are skipped", g:nextEmpty(1, 1) == 4, g:nextEmpty(1, 1))

-- Fill every cell but one: the jump lands there from anywhere, and from the
-- last empty cell itself there's nowhere to go.
g = newGame()
for i = 1, 81 do
    if i ~= 41 and g.values[i] == 0 then g:enter(i, g.solution[i], settings) end
end
check("only one empty cell, forward", g:nextEmpty(1, 1) == 41, g:nextEmpty(1, 1))
check("only one empty cell, backward", g:nextEmpty(81, -1) == 41, g:nextEmpty(81, -1))
check("no other empty cell", g:nextEmpty(41, 1) == nil and g:nextEmpty(41, -1) == nil)

-- nextNeededDigit ---------------------------------------------------------------

g = newGame()
check("next number", g:nextNeededDigit(4, 1) == 5, g:nextNeededDigit(4, 1))
check("previous number", g:nextNeededDigit(4, -1) == 3, g:nextNeededDigit(4, -1))
check("wraps 9 to 1", g:nextNeededDigit(9, 1) == 1, g:nextNeededDigit(9, 1))
check("wraps 1 to 9", g:nextNeededDigit(1, -1) == 9, g:nextNeededDigit(1, -1))
for i = 1, 81 do
    if g.values[i] == 0 and (g.solution[i] == 5 or g.solution[i] == 6) then
        g:enter(i, g.solution[i], settings)
    end
end
check("skips numbers placed nine times", g:nextNeededDigit(4, 1) == 7, g:nextNeededDigit(4, 1))
check("skips them going back too", g:nextNeededDigit(7, -1) == 4, g:nextNeededDigit(7, -1))
for i = 1, 81 do
    if g.values[i] == 0 then g:enter(i, g.solution[i], settings) end
end
check("all placed: just the next one", g:nextNeededDigit(4, 1) == 5, g:nextNeededDigit(4, 1))

-- checkPlaced -------------------------------------------------------------------

g = newGame()
local placed, wrong = g:checkPlaced()
check("fresh puzzle: nothing placed", placed == 0 and wrong == 0, placed .. "/" .. wrong)
g:enter(3, 4, settings)       -- right
g:enter(4, 5, settings)       -- wrong (the answer is 6)
g:toggleNote(6, 8)            -- notes don't count
placed, wrong = g:checkPlaced()
check("counts placed and wrong", placed == 2 and wrong == 1, placed .. "/" .. wrong)
g:hint(7)                     -- hinted cells lock, like givens
placed, wrong = g:checkPlaced()
check("hinted cells left out", placed == 2 and wrong == 1, placed .. "/" .. wrong)
check("checking doesn't change the board", g.values[4] == 5)

-- L2 / R2 -------------------------------------------------------------------------

local fired = {}
input.handler = function(a) fired[#fired + 1] = a end
local function take()
    local out = table.concat(fired, " ")
    fired = {}
    return out
end

input.gamepadaxis(nil, "triggerright", 1.0)
check("R2 pull fires r2", take() == "r2")
input.gamepadaxis(nil, "triggerright", 0.5)
check("still held between thresholds", take() == "")
input.update(0.3)
check("holding R2 repeats", take() == "r2")
input.gamepadaxis(nil, "triggerright", 0.0)
input.update(0.5)
check("release stops repeating", take() == "")
input.gamepadaxis(nil, "triggerleft", 0.7)
input.gamepadaxis(nil, "triggerleft", 0.45)
input.gamepadaxis(nil, "triggerleft", 0.65)
check("no flicker around one threshold", take() == "l2")
input.gamepadaxis(nil, "triggerleft", 0.2)
input.gamepadaxis(nil, "triggerleft", 0.9)
check("pulling again fires again", take() == "l2")
input.gamepadaxis(nil, "triggerleft", 0.0)
input.keypressed("pagedown", false)
input.keyreleased("pagedown")
input.keypressed("pageup", false)
input.keyreleased("pageup")
check("Page Down / Page Up are R2 / L2", take() == "r2 l2")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
