-- One Solo puzzle in progress: the numbers, the player's marks and the undo
-- history. No drawing or input here; the play screen calls these methods and
-- reacts to the results. Pure Lua, testable with luajit.

local solo = require("src.solo")

local MAX_HISTORY = 300

-- What the player put in a cell: nothing, shading, or a dot (marked to stay
-- unshaded).
local NONE, SHADE, DOT = 0, 1, 2

local SoloGame = {}
SoloGame.__index = SoloGame
SoloGame.NONE, SoloGame.SHADE, SoloGame.DOT = NONE, SHADE, DOT

function SoloGame.new(generated, difficulty)
    local g = setmetatable({}, SoloGame)
    local n = generated.size
    g.size, g.difficulty = n, difficulty
    g.values = solo.copy(generated.values)
    g.solution, g.marks = {}, {}
    for i = 1, n * n do
        g.solution[i] = generated.solution[i] == solo.SHADED
        g.marks[i] = NONE
    end
    g.elapsed = 0
    g.cursor = math.floor(n * n / 2) + 1 -- the middle
    g.undoStack, g.redoStack = {}, {}
    g.solved = false
    return g
end

-- Queries ---------------------------------------------------------------------

function SoloGame:shadedSet()
    local shaded = {}
    for i, m in ipairs(self.marks) do shaded[i] = (m == SHADE) end
    return shaded
end

-- Any shading that keeps the rules counts, not only the one it was built
-- from (the two only differ if extra cells are shaded).
function SoloGame:isSolved()
    return solo.check(self.size, self.values, self:shadedSet())
end

-- Marks the puzzle solved if it is. Returns true if it is.
function SoloGame:checkSolved()
    if not self.solved and self:isSolved() then self.solved = true end
    return self.solved
end

-- The unshaded cells whose number another unshaded cell in their row or
-- column also has: repeats[i] = true.
function SoloGame:repeats()
    local repeats = {}
    for _, line in ipairs(solo.geometry(self.size).lines) do
        local seen = {} -- [value] = the first unshaded cell with it
        for _, i in ipairs(line) do
            if self.marks[i] ~= SHADE then
                local v = self.values[i]
                local first = seen[v]
                if first then
                    repeats[first], repeats[i] = true, true
                else
                    seen[v] = i
                end
            end
        end
    end
    return repeats
end

-- Rows and columns without an unshaded repeat, and how many there are.
function SoloGame:clearLines()
    local clear = 0
    for _, line in ipairs(solo.geometry(self.size).lines) do
        local used, ok = {}, true
        for _, i in ipairs(line) do
            if self.marks[i] ~= SHADE then
                local v = self.values[i]
                if used[v] then
                    ok = false
                    break
                end
                used[v] = true
            end
        end
        if ok then clear = clear + 1 end
    end
    return clear, 2 * self.size
end

-- Changes ---------------------------------------------------------------------
-- Each returns { changed, mark, solved }.

function SoloGame:setMark(i, mark)
    local before = self.marks[i]
    if before == mark then return { changed = false } end
    self.marks[i] = mark
    local stack = self.undoStack
    stack[#stack + 1] = { i, before, mark }
    if #stack > MAX_HISTORY then table.remove(stack, 1) end
    self.redoStack = {}
    return { changed = true, mark = mark, solved = self:checkSolved() }
end

function SoloGame:toggleShade(i)
    return self:setMark(i, self.marks[i] == SHADE and NONE or SHADE)
end

function SoloGame:toggleDot(i)
    return self:setMark(i, self.marks[i] == DOT and NONE or DOT)
end

function SoloGame:clear(i)
    return self:setMark(i, NONE)
end

-- Undo and redo return the cell that changed, or nil.
function SoloGame:undo()
    local e = table.remove(self.undoStack)
    if not e then return nil end
    self.redoStack[#self.redoStack + 1] = e
    self.marks[e[1]] = e[2]
    return e[1]
end

function SoloGame:redo()
    local e = table.remove(self.redoStack)
    if not e then return nil end
    self.undoStack[#self.undoStack + 1] = e
    self.marks[e[1]] = e[3]
    return e[1]
end

function SoloGame:restart()
    for i = 1, self.size * self.size do self.marks[i] = NONE end
    self.elapsed = 0
    self.undoStack, self.redoStack = {}, {}
    self.solved = false
end

-- Saving ----------------------------------------------------------------------

function SoloGame:serialize()
    local solution = {}
    for i, s in ipairs(self.solution) do solution[i] = s and "1" or "0" end
    return {
        version = 1,
        size = self.size,
        difficulty = self.difficulty,
        values = table.concat(self.values),
        solution = table.concat(solution),
        marks = table.concat(self.marks),
        elapsed = self.elapsed,
        cursor = self.cursor,
        undoStack = self.undoStack,
        redoStack = self.redoStack,
    }
end

local LEVELS = { easy = true, medium = true, hard = true }

-- Keeps history entries that name a cell and two marks.
local function cleanStack(list, count)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        if type(e) == "table" then
            local i, a, b = tonumber(e[1]), tonumber(e[2]), tonumber(e[3])
            if i and i >= 1 and i <= count and a and a >= 0 and a <= 2 and b and b >= 0 and b <= 2 then
                out[#out + 1] = { i, a, b }
            end
        end
    end
    return out
end

function SoloGame.deserialize(t)
    if type(t) ~= "table" or t.version ~= 1 then return nil end
    local n = tonumber(t.size)
    local count = n and n * n
    if not count or n < 2 or n > 9 then return nil end
    if type(t.values) ~= "string" or #t.values ~= count then return nil end
    if type(t.solution) ~= "string" or #t.solution ~= count then return nil end
    if type(t.marks) ~= "string" or #t.marks ~= count then return nil end
    local g = setmetatable({}, SoloGame)
    g.size = n
    g.difficulty = LEVELS[t.difficulty] and t.difficulty or "medium"
    g.values, g.solution, g.marks = {}, {}, {}
    for i = 1, count do
        local v, m = tonumber(t.values:sub(i, i)), tonumber(t.marks:sub(i, i))
        if not v or v < 1 or v > n then return nil end
        g.values[i] = v
        g.solution[i] = t.solution:sub(i, i) == "1"
        g.marks[i] = (m and m >= 0 and m <= 2) and m or NONE
    end
    g.elapsed = tonumber(t.elapsed) or 0
    g.cursor = math.max(1, math.min(count, tonumber(t.cursor) or 1))
    g.undoStack = cleanStack(t.undoStack, count)
    g.redoStack = cleanStack(t.redoStack, count)
    g.solved = g:isSolved()
    return g
end

return SoloGame
