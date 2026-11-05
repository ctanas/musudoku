-- One Pairlink puzzle in progress: the numbers, the player's lines and the
-- undo history. No drawing or input here; the play screen calls these
-- methods and reacts to the results. Pure Lua, testable with luajit.
--
-- lines[k] is pair k's line as a list of cells, starting at one of its
-- numbers, or {} when there's none. A stroke is one go at drawing: it begins
-- on a number or a line, steps cell by cell (stepping back along the line
-- takes steps back), and ends. Each stroke, and each erased line, is one
-- undo step.

local pairlink = require("src.pairlink")

local MAX_HISTORY = 300

local PairGame = {}
PairGame.__index = PairGame

local function copy(t)
    local out = {}
    for i = 1, #t do out[i] = t[i] end
    return out
end

local function indexOf(list, x)
    for s, v in ipairs(list) do
        if v == x then return s end
    end
end

local function sameLine(a, b)
    if #a ~= #b then return false end
    for s = 1, #a do
        if a[s] ~= b[s] then return false end
    end
    return true
end

function PairGame.new(generated, difficulty)
    local g = setmetatable({}, PairGame)
    g.size, g.difficulty = generated.size, difficulty
    g.clues = copy(generated.clues)
    g.ends, g.pairs = pairlink.ends(g.size, g.clues)
    g.solution = {}
    for k, line in ipairs(generated.lines) do g.solution[k] = copy(line) end
    g.lines = {}
    for k = 1, g.pairs do g.lines[k] = {} end
    g.elapsed = 0
    g.cursor = math.floor(g.size * g.size / 2) + 1
    g.undoStack, g.redoStack = {}, {}
    g.solved = false
    g:rebuildOwners()
    return g
end

-- owner[i] is the pair whose line uses cell i, or 0.
function PairGame:rebuildOwners()
    self.owner = {}
    for i = 1, self.size * self.size do self.owner[i] = 0 end
    for k, line in ipairs(self.lines) do
        for _, i in ipairs(line) do self.owner[i] = k end
    end
end

-- Queries ---------------------------------------------------------------------

-- True when pair k's line runs from one of its numbers to the other.
function PairGame:isLinked(k)
    local line = self.lines[k]
    return #line >= 2 and self.clues[line[#line]] == k
end

function PairGame:linkedCount()
    local n = 0
    for k = 1, self.pairs do
        if self:isLinked(k) then n = n + 1 end
    end
    return n
end

function PairGame:filledCount()
    local n = 0
    for _, k in ipairs(self.owner) do
        if k ~= 0 then n = n + 1 end
    end
    return n
end

function PairGame:isSolved()
    return pairlink.check(self.size, self.clues, self.lines)
end

function PairGame:checkSolved()
    if not self.solved and self:isSolved() then self.solved = true end
    return self.solved
end

-- The pair whose line or number is at cell i, or 0.
function PairGame:pairAt(i)
    local k = self.owner[i]
    if k == 0 then k = self.clues[i] end
    return k
end

-- History ---------------------------------------------------------------------
-- An entry is { pair, lineBefore, lineAfter }.

function PairGame:record(k, before, after)
    local stack = self.undoStack
    stack[#stack + 1] = { k, before, after }
    if #stack > MAX_HISTORY then table.remove(stack, 1) end
    self.redoStack = {}
end

-- Undo and redo return a cell to put the cursor on, or nil.
local function restore(self, k, line)
    self.lines[k] = copy(line)
    self:rebuildOwners()
    return line[#line] or self.ends[k][1]
end

function PairGame:undo()
    local e = table.remove(self.undoStack)
    if not e then return nil end
    self.redoStack[#self.redoStack + 1] = e
    return restore(self, e[1], e[2])
end

function PairGame:redo()
    local e = table.remove(self.redoStack)
    if not e then return nil end
    self.undoStack[#self.undoStack + 1] = e
    return restore(self, e[1], e[3])
end

-- Drawing ---------------------------------------------------------------------

-- Begins a stroke at cell i. On a number, a new line starts there (the
-- pair's old line goes). On a line, the line is cut back to that cell to go
-- on from there. Returns the pair, or nil on an empty cell.
function PairGame:begin(i)
    local k = self.clues[i]
    if k ~= 0 then
        self.before = copy(self.lines[k])
        self.lines[k] = { i }
    else
        k = self.owner[i]
        if k == 0 then return nil end
        self.before = copy(self.lines[k])
        local line = self.lines[k]
        for s = #line, indexOf(line, i) + 1, -1 do line[s] = nil end
    end
    self.active = k
    self:rebuildOwners()
    return k
end

-- One step of the stroke into cell j, a neighbour of the line's last cell.
-- Returns { moved, back, linked } or { blocked = true }.
function PairGame:step(j)
    local k = self.active
    local line = self.lines[k]
    local at = indexOf(line, j)
    if at then
        -- back along its own line
        for s = #line, at + 1, -1 do
            self.owner[line[s]] = 0
            line[s] = nil
        end
        return { moved = true, back = true }
    end
    local c = self.clues[j]
    if c == k then
        line[#line + 1] = j
        self.owner[j] = k
        return { moved = true, linked = true }
    end
    if c ~= 0 or self.owner[j] ~= 0 then return { blocked = true } end
    line[#line + 1] = j
    self.owner[j] = k
    return { moved = true }
end

-- The last cell of the line being drawn.
function PairGame:head()
    local line = self.lines[self.active]
    return line[#line]
end

-- Ends the stroke. Returns { changed, pair, solved }.
function PairGame:finish()
    local k = self.active
    if not k then return { changed = false } end
    self.active = nil
    if #self.lines[k] == 1 then
        -- just the number: no line
        self.lines[k] = {}
        self:rebuildOwners()
    end
    local before, after = self.before, self.lines[k]
    self.before = nil
    if sameLine(before, after) then return { changed = false, pair = k } end
    self:record(k, before, copy(after))
    return { changed = true, pair = k, solved = self:checkSolved() }
end

-- Removes the line through cell i (or from its number). Returns
-- { changed, pair }.
function PairGame:erase(i)
    local k = self:pairAt(i)
    if k == 0 or #self.lines[k] == 0 then return { changed = false } end
    self:record(k, copy(self.lines[k]), {})
    self.lines[k] = {}
    self:rebuildOwners()
    return { changed = true, pair = k }
end

function PairGame:restart()
    for k = 1, self.pairs do self.lines[k] = {} end
    self:rebuildOwners()
    self.active, self.before = nil, nil
    self.elapsed = 0
    self.undoStack, self.redoStack = {}, {}
    self.solved = false
end

-- Saving ----------------------------------------------------------------------

function PairGame:serialize()
    return {
        version = 1,
        size = self.size,
        difficulty = self.difficulty,
        clues = self.clues,
        solution = self.solution,
        lines = self.lines,
        elapsed = self.elapsed,
        cursor = self.cursor,
        undoStack = self.undoStack,
        redoStack = self.redoStack,
    }
end

local LEVELS = { easy = true, medium = true, hard = true }

-- A saved line for pair k: from one of its numbers, cell by cell side by
-- side, through free cells only. {} if it isn't one.
local function cleanLine(g, k, line, used)
    if type(line) ~= "table" or #line == 0 then return {} end
    local geo = pairlink.geometry(g.size)
    local out = {}
    for s, v in ipairs(line) do
        local i = tonumber(v)
        if not i or not geo.edgeAt[i] or used[i] then return {} end
        if s == 1 and g.clues[i] ~= k then return {} end
        if s > 1 and not geo.edgeAt[out[s - 1]][i] then return {} end
        if s > 1 and g.clues[i] ~= 0 and (g.clues[i] ~= k or s < #line) then return {} end
        out[s] = i
    end
    if #out < 2 then return {} end
    for _, i in ipairs(out) do used[i] = true end
    return out
end

local function cleanStack(list, pairs)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        local k = type(e) == "table" and tonumber(e[1])
        if not (k and k >= 1 and k <= pairs and type(e[2]) == "table" and type(e[3]) == "table") then
            return {} -- something's off: drop the history rather than guess
        end
        out[#out + 1] = { k, e[2], e[3] }
    end
    return out
end

function PairGame.deserialize(t)
    if type(t) ~= "table" or t.version ~= 1 then return nil end
    local n = tonumber(t.size)
    if not n or n < 2 or n > 12 or type(t.clues) ~= "table" or #t.clues ~= n * n then return nil end
    local g = setmetatable({}, PairGame)
    g.size = n
    g.difficulty = LEVELS[t.difficulty] and t.difficulty or "medium"
    g.clues = {}
    for i = 1, n * n do g.clues[i] = tonumber(t.clues[i]) or 0 end
    g.ends, g.pairs = pairlink.ends(n, g.clues)
    if not g.ends then return nil end
    g.solution = {}
    for k = 1, g.pairs do
        g.solution[k] = cleanLine(g, k, type(t.solution) == "table" and t.solution[k], {})
    end
    if not pairlink.check(n, g.clues, g.solution) then return nil end
    g.lines = {}
    local used = {}
    for k = 1, g.pairs do
        g.lines[k] = cleanLine(g, k, type(t.lines) == "table" and t.lines[k], used)
    end
    g:rebuildOwners()
    g.elapsed = tonumber(t.elapsed) or 0
    g.cursor = math.max(1, math.min(n * n, tonumber(t.cursor) or 1))
    g.undoStack = cleanStack(t.undoStack, g.pairs)
    g.redoStack = cleanStack(t.redoStack, g.pairs)
    g.solved = g:isSolved()
    return g
end

return PairGame
