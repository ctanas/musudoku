-- Run from the repository root:  luajit tests/test_puzzlegames.lua
-- Solo, Pairlink and Hoshi puzzles in progress: marks, lines and bridges,
-- undo and redo, solving, and saving.
package.path = "./game/?.lua;" .. package.path
local solo = require("src.solo")
local pairlink = require("src.pairlink")
local SoloGame = require("src.sologame")
local PairGame = require("src.pairgame")
local hoshi = require("src.hoshi")
local HoshiGame = require("src.hoshigame")

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

-- Hoshi -----------------------------------------------------------------------
-- 3x3 square: a double bridge along the top, singles down both sides.

local square = {
    size = 3,
    clues = { 3, 0, 3, 0, 0, 0, 1, 0, 1 },
    bridges = { { 1, 3, 2 }, { 1, 7, 1 }, { 3, 9, 1 } },
}
local h = HoshiGame.new(square, "easy")
check("hoshi starts unsolved", not h.solved and h:doneCount() == 0 and h:islandCount() == 4)
check("hoshi cursor on an island", h:isIsland(h.cursor))
check("no island that way", h:cycle(1, "up").blocked == "none")
res = h:cycle(1, "right")
check("a bridge", res.changed and res.added and res.count == 1 and h:bridgesAt(1) == 1 and h:bridgesAt(3) == 1)
res = h:cycle(1, "right")
check("a second bridge", res.count == 2 and h:bridgesAt(3) == 2)
res = h:cycle(3, "left")
check("a third press takes them away", res.changed and not res.added and res.count == 0 and h:bridgesAt(1) == 0)
local bottom = h:linkToward(7, "right")
h:cycle(7, "right")
check("between two 1s, one bridge", h.counts[bottom] == 1)
h:cycle(9, "left")
check("then none", h.counts[bottom] == 0)
check("undo", h:undo() == 9 and h.counts[bottom] == 1)
check("redo", h:redo() == 9 and h.counts[bottom] == 0)

h:cycle(7, "up")
check("an island with its number is done", h:state(7) == "done" and h:doneCount() == 1)
h:cycle(7, "right")
check("one with more is over", h:state(7) == "over" and h:state(9) == "done")
h:undo()
h:cycle(1, "right")
h:cycle(1, "right")
check("both ends of a double", h:state(1) == "done" and h:state(3) == "short")
res = h:clearIsland(1)
check("clearing an island", res.changed and #res.links == 2 and h:bridgesAt(1) == 0 and h:bridgesAt(3) == 0)
check("clearing nothing", not h:clearIsland(1).changed)
check("undoing a clear", h:undo() == 1 and h:bridgesAt(1) == 3)
check("not solved yet", not h.solved and h:nextUnfinished(1, 1) == 3)
res = h:cycle(3, "down")
check("the last bridge solves it", res.solved and h.solved and h:nextUnfinished(1, 1) == nil)
check("next island in line", h:nextIsland(1, "right") == 3 and h:nextIsland(1, "down") == 7)
check("no island that way to move to", h:nextIsland(1, "left") == nil and h:nextIsland(9, "down") == nil)

local h2 = HoshiGame.deserialize(roundTrip(h:serialize()))
check("hoshi loads", h2 ~= nil)
check("hoshi loads bridges and solved", h2 and h2.solved and h2:bridgesAt(1) == 3 and h2:doneCount() == 4)
check("hoshi loads history", h2 and #h2.undoStack == #h.undoStack and h2:undo() ~= nil)
local badAnswer = h:serialize()
badAnswer.solution = { { 1, 3, 1 } }
check("hoshi rejects a save whose answer isn't one", HoshiGame.deserialize(roundTrip(badAnswer)) == nil)
local badBridges = h:serialize()
badBridges.bridges = { { 1, 9, 1 } }
local h3 = HoshiGame.deserialize(roundTrip(badBridges))
check("bridges that aren't links are dropped", h3 and h3:bridgesAt(1) == 0 and #h3.undoStack == 0 and not h3.solved)
check("hoshi rejects a broken save", HoshiGame.deserialize({ version = 1, size = 3, clues = { 1 } }) == nil)
h:restart()
check("hoshi restart", not h.solved and h:bridgesAt(1) == 0 and #h.undoStack == 0 and h.elapsed == 0)

-- 5x5: a row and a column cross in the middle; the answer uses the row.
local crossing = {
    size = 5,
    clues = { 0, 0, 1, 0, 2, 0, 0, 0, 0, 0, 1, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 1, 0, 2 },
    bridges = { { 11, 15, 1 }, { 3, 5, 1 }, { 5, 15, 1 }, { 15, 25, 1 }, { 23, 25, 1 } },
}
local hc = HoshiGame.new(crossing, "easy")
hc:cycle(11, "right")
res = hc:cycle(3, "down")
check("a bridge can't cross another", res.blocked == "cross" and res.link == hc:linkToward(11, "right"))
hc:undo()
check("once it's gone, it can", hc:cycle(3, "down").changed)

-- a generated puzzle solves with its own bridges, built the way a player would
local genH = hoshi.generate(9, "hard", rng)
local hg = HoshiGame.new(genH, "hard")
for _, b in ipairs(genH.bridges) do
    local l = hoshi.linkBetween(hg.P, b[1], b[2])
    local link = hg.P.links[l]
    for _ = 1, b[3] do res = hg:cycle(link.a, link.horizontal and "right" or "down") end
end
check("generated hoshi solves with its bridges", res.solved and hg:doneCount() == hg:islandCount())

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
