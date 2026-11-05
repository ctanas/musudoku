-- Run from the repository root:  luajit tests/test_puzzlegames.lua
-- Solo and Pairlink puzzles in progress: marks and lines, undo and redo,
-- solving, and saving.
package.path = "./game/?.lua;" .. package.path
local solo = require("src.solo")
local pairlink = require("src.pairlink")
local SoloGame = require("src.sologame")
local PairGame = require("src.pairgame")

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

-- A round trip through the save file's text, like storage.lua does.
local function roundTrip(t)
    local function ser(v, out)
        local ty = type(v)
        if ty == "number" then out[#out + 1] = string.format("%.17g", v)
        elseif ty == "string" then out[#out + 1] = string.format("%q", v)
        elseif ty == "boolean" then out[#out + 1] = tostring(v)
        elseif ty == "table" then
            out[#out + 1] = "{"
            for k, x in pairs(v) do
                out[#out + 1] = "["
                ser(k, out)
                out[#out + 1] = "]="
                ser(x, out)
                out[#out + 1] = ","
            end
            out[#out + 1] = "}"
        end
    end
    local out = { "return " }
    ser(t, out)
    return loadstring(table.concat(out))()
end

math.randomseed(3)
local function rng(n) return math.random(n) end

-- Solo ------------------------------------------------------------------------

local gen = solo.generate(5, "easy", rng)
local g = SoloGame.new(gen, "easy")
check("solo starts unsolved", not g.solved and not g:isSolved())
check("solo cursor in the middle", g.cursor == 13)

local shadedCell
for i = 1, 25 do if g.solution[i] then shadedCell = i break end end
local res = g:toggleShade(shadedCell)
check("shading changes the mark", res.changed and g.marks[shadedCell] == SoloGame.SHADE)
res = g:toggleShade(shadedCell)
check("shading again clears it", res.changed and g.marks[shadedCell] == SoloGame.NONE)
g:toggleDot(1)
check("dot", g.marks[1] == SoloGame.DOT)
g:clear(1)
check("clear", g.marks[1] == SoloGame.NONE)
check("clearing nothing changes nothing", not g:clear(1).changed)
check("undo goes back", g:undo() == 1 and g.marks[1] == SoloGame.DOT)
check("redo goes forward", g:redo() == 1 and g.marks[1] == SoloGame.NONE)

-- solve it with the solution's shading
local last
for i = 1, 25 do
    if g.solution[i] then
        if last then g:toggleShade(last) end
        last = i
    end
end
check("one short of solved", not g.solved)
res = g:toggleShade(last)
check("last shading solves it", res.solved and g.solved)
local clear, total = g:clearLines()
check("solved board has no repeats", clear == total and total == 10)

-- saving
local g2 = SoloGame.deserialize(roundTrip(g:serialize()))
check("solo loads", g2 ~= nil)
check("solo loads marks and solved", g2 and g2.solved and g2.marks[last] == SoloGame.SHADE)
check("solo loads history", g2 and #g2.undoStack == #g.undoStack)
local broken = g:serialize()
broken.values = "12"
check("solo rejects a broken save", SoloGame.deserialize(broken) == nil)
g:restart()
check("restart clears", not g.solved and g.marks[last] == SoloGame.NONE and #g.undoStack == 0)

-- Pairlink --------------------------------------------------------------------
-- 4x4 rows puzzle: pair k runs along row k.

local rows = {
    size = 4,
    clues = { 1, 0, 0, 1, 2, 0, 0, 2, 3, 0, 0, 3, 4, 0, 0, 4 },
    lines = { { 1, 2, 3, 4 }, { 5, 6, 7, 8 }, { 9, 10, 11, 12 }, { 13, 14, 15, 16 } },
}
local p = PairGame.new(rows, "easy")
check("pairlink starts empty", p:filledCount() == 0 and p:linkedCount() == 0)
check("begin on an empty cell fails", p:begin(2) == nil)
check("begin on a number", p:begin(1) == 1 and p.owner[1] == 1)
check("step into another number is blocked", p:step(5).blocked and p.owner[5] == 0)
check("step right", p:step(2).moved and p.owner[2] == 1)
check("step back", p:step(1).back and #p.lines[1] == 1 and p.owner[2] == 0)
p:step(2)
p:step(3)
res = p:step(4)
check("reaching the other number links", res.linked and p:isLinked(1))
res = p:finish()
check("finish records the stroke", res.changed and #p.undoStack == 1)

-- a stroke that wanders and comes back is cut back to where it is
p:begin(5)
p:step(6)
p:step(10) -- down into row 3
check("a line can leave its row", p.owner[10] == 2)
p:step(6) -- back along its own line
check("stepping onto its own line cuts back", #p.lines[2] == 2 and p.owner[10] == 0)
p:finish()

-- beginning on a line cuts it back there
p:begin(6)
check("begin on a line keeps it up to there", #p.lines[2] == 2 and p.active == 2)
p:step(7)
p:step(8)
p:finish()
check("row 2 linked", p:isLinked(2))

-- a number alone isn't a line
p:begin(9)
res = p:finish()
check("number alone leaves no line", #p.lines[3] == 0 and not res.changed)

-- erase and undo
check("erase a line", p:erase(3).changed and #p.lines[1] == 0 and p.owner[3] == 0)
check("erase nothing", not p:erase(10).changed)
check("undo the erase", p:undo() == 4 and p:isLinked(1))

for k = 3, 4 do
    local a = (k - 1) * 4 + 1
    p:begin(a)
    for s = 1, 3 do p:step(a + s) end
    res = p:finish()
end
check("all rows solve it", res.solved and p.solved and p:filledCount() == 16)

local p2 = PairGame.deserialize(roundTrip(p:serialize()))
check("pairlink loads", p2 ~= nil)
check("pairlink loads lines", p2 and p2.solved and p2:linkedCount() == 4)
local tampered = p:serialize()
tampered.lines = { { 1, 3 }, { 5, 6, 7, 8 }, { 9, 10, 11, 12 }, { 13, 14, 15, 16 } }
local p3 = PairGame.deserialize(roundTrip(tampered))
check("a broken line is dropped on load", p3 and #p3.lines[1] == 0 and not p3.solved)
check("pairlink rejects a broken save", PairGame.deserialize({ version = 1, size = 4, clues = { 1 } }) == nil)

-- a generated puzzle can be solved with its own lines
local genL = pairlink.generate(7, "medium", rng)
local pg = PairGame.new(genL, "medium")
for k, line in ipairs(genL.lines) do
    pg:begin(line[1])
    for s = 2, #line do pg:step(line[s]) end
    res = pg:finish()
end
check("generated pairlink solves with its lines", res.solved)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
