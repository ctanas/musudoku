-- One Hoshi puzzle in progress: the islands, the player's bridges and the
-- undo history. No drawing or input here; the play screen calls these
-- methods and reacts to the results. Pure Lua, testable with luajit.
--
-- counts[l] is how many bridges (0 to 2) the player has put on link l (see
-- hoshi.analyze). The cursor is always on an island. Each change, a bridge
-- added or taken away or an island cleared, is one undo step.

local hoshi = require("src.hoshi")

local MAX_HISTORY = 300

local HoshiGame = {}
HoshiGame.__index = HoshiGame

local function copy(t)
    local out = {}
    for i = 1, #t do out[i] = t[i] end
    return out
end

local function copyList(list)
    local out = {}
    for k, e in ipairs(list) do out[k] = { e[1], e[2], e[3] } end
    return out
end

-- The island nearest the middle of the board, to start on.
local function middleIsland(P)
    local n, best, bestD = P.n, P.islands[1], math.huge
    local mid = (n - 1) / 2
    for _, i in ipairs(P.islands) do
        local r, c = math.floor((i - 1) / n), (i - 1) % n
        local d = (r - mid) ^ 2 + (c - mid) ^ 2
        if d < bestD then best, bestD = i, d end
    end
    return best
end

local function setup(g, n, clues)
    g.size, g.clues = n, clues
    g.P = hoshi.analyze(n, clues)
    g.counts = {}
    for l = 1, #g.P.links do g.counts[l] = 0 end
end

function HoshiGame.new(generated, difficulty)
    local g = setmetatable({}, HoshiGame)
    setup(g, generated.size, copy(generated.clues))
    g.difficulty = difficulty
    g.solution = copyList(generated.bridges)
    g.elapsed = 0
    g.cursor = middleIsland(g.P)
    g.undoStack, g.redoStack = {}, {}
    g.solved = false
    return g
end

-- Queries ---------------------------------------------------------------------

function HoshiGame:isIsland(i)
    return self.P.index[i] ~= nil
end

-- How many bridges end at island i.
function HoshiGame:bridgesAt(i)
    local k = self.P.index[i]
    if not k then return 0 end
    local sum = 0
    for _, l in ipairs(self.P.linksOf[k]) do sum = sum + self.counts[l] end
    return sum
end

-- "short", "done" or "over": island i's bridges against its number.
function HoshiGame:state(i)
    local have, need = self:bridgesAt(i), self.clues[i]
    if have == need then return "done" end
    return have < need and "short" or "over"
end

function HoshiGame:islandCount()
    return #self.P.islands
end

function HoshiGame:doneCount()
    local n = 0
    for _, i in ipairs(self.P.islands) do
        if self:state(i) == "done" then n = n + 1 end
    end
    return n
end

-- The link from island i in a direction ("up", "down", "left", "right").
function HoshiGame:linkToward(i, dir)
    local toward = self.P.toward[i]
    return toward and toward[dir]
end

-- A link with bridges on it that link l would cross, or nil.
function HoshiGame:crossing(l)
    for _, m in ipairs(self.P.crosses[l]) do
        if self.counts[m] > 0 then return m end
    end
end

function HoshiGame:isSolved()
    return hoshi.check(self.P, self.counts)
end

function HoshiGame:checkSolved()
    if not self.solved and self:isSolved() then self.solved = true end
    return self.solved
end

-- Moving between islands ----------------------------------------------------------

-- The island to go to from island i in a direction: the next one in line,
-- or if there's none, the nearest one that way (straighter first). Nil if
-- there's no island that way at all.
function HoshiGame:nextIsland(i, dir)
    local l = self:linkToward(i, dir)
    if l then
        local link = self.P.links[l]
        return link.a == i and link.b or link.a
    end
    local d = hoshi.DIRS[dir]
    local n = self.size
    local r0, c0 = math.floor((i - 1) / n), (i - 1) % n
    local best, bestScore
    for _, j in ipairs(self.P.islands) do
        local dr, dc = math.floor((j - 1) / n) - r0, (j - 1) % n - c0
        local along = dr * d[1] + dc * d[2]
        if along > 0 then
            local across = math.abs(dr * d[2] - dc * d[1])
            local score = along + across * 2
            if not best or score < bestScore then best, bestScore = j, score end
        end
    end
    return best
end

-- The next island (dir 1) or the one before (dir -1) in reading order that
-- doesn't have its number of bridges yet, or nil if they all do.
function HoshiGame:nextUnfinished(i, dir)
    local islands = self.P.islands
    local k = self.P.index[i] or 0
    for s = 1, #islands do
        local j = islands[(k - 1 + dir * s) % #islands + 1]
        if self:state(j) ~= "done" then return j end
    end
end

-- History ---------------------------------------------------------------------
-- An entry is { at = island, { link, before, after }, ... }.

function HoshiGame:record(entry)
    local stack = self.undoStack
    stack[#stack + 1] = entry
    if #stack > MAX_HISTORY then table.remove(stack, 1) end
    self.redoStack = {}
end

-- Undo and redo return the island to put the cursor on, or nil.
function HoshiGame:undo()
    local e = table.remove(self.undoStack)
    if not e then return nil end
    self.redoStack[#self.redoStack + 1] = e
    for _, change in ipairs(e) do self.counts[change[1]] = change[2] end
    return e.at
end

function HoshiGame:redo()
    local e = table.remove(self.redoStack)
    if not e then return nil end
    self.undoStack[#self.undoStack + 1] = e
    for _, change in ipairs(e) do self.counts[change[1]] = change[3] end
    return e.at
end

-- Building --------------------------------------------------------------------

-- Adds a bridge from island i in a direction: none, one, two, then none
-- again (one, then none, where an island's number is 1). Returns
-- { changed, link, count, added, solved }, or { blocked = "none" } when
-- there's no island that way and { blocked = "cross", link } when a bridge
-- is in the way.
function HoshiGame:cycle(i, dir)
    local l = self:linkToward(i, dir)
    if not l then return { blocked = "none" } end
    local before = self.counts[l]
    local after = (before + 1) % (self.P.links[l].max + 1)
    if before == 0 and after > 0 then
        local m = self:crossing(l)
        if m then return { blocked = "cross", link = m } end
    end
    self.counts[l] = after
    self:record({ at = i, { l, before, after } })
    return { changed = true, link = l, count = after, added = after > before, solved = self:checkSolved() }
end

-- Takes away every bridge at island i. Returns { changed, links }.
function HoshiGame:clearIsland(i)
    local k = self.P.index[i]
    if not k then return { changed = false } end
    local entry, links = { at = i }, {}
    for _, l in ipairs(self.P.linksOf[k]) do
        if self.counts[l] > 0 then
            entry[#entry + 1] = { l, self.counts[l], 0 }
            links[#links + 1] = l
            self.counts[l] = 0
        end
    end
    if #entry == 0 then return { changed = false } end
    self:record(entry)
    return { changed = true, links = links }
end

function HoshiGame:restart()
    for l = 1, #self.P.links do self.counts[l] = 0 end
    self.elapsed = 0
    self.undoStack, self.redoStack = {}, {}
    self.solved = false
end

-- Saving ----------------------------------------------------------------------

function HoshiGame:serialize()
    return {
        version = 1,
        size = self.size,
        difficulty = self.difficulty,
        clues = self.clues,
        solution = self.solution,
        bridges = hoshi.toList(self.P, self.counts),
        elapsed = self.elapsed,
        cursor = self.cursor,
        undoStack = self.undoStack,
        redoStack = self.redoStack,
    }
end

local LEVELS = { easy = true, medium = true, hard = true }

-- A saved list of { a, b, count } as clean entries, or nil.
local function cleanList(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, e in ipairs(list) do
        if type(e) ~= "table" then return nil end
        local a, b, c = tonumber(e[1]), tonumber(e[2]), tonumber(e[3])
        if not (a and b and c) then return nil end
        out[#out + 1] = { a, b, c }
    end
    return out
end

local function cleanStack(list, links)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        if type(e) ~= "table" or not tonumber(e.at) or #e == 0 then return {} end
        local entry = { at = tonumber(e.at) }
        for _, change in ipairs(e) do
            local l, before, after = type(change) == "table" and tonumber(change[1]),
                type(change) == "table" and tonumber(change[2]), type(change) == "table" and tonumber(change[3])
            if not (l and before and after and l >= 1 and l <= links
                and before >= 0 and before <= 2 and after >= 0 and after <= 2) then
                return {} -- something's off: drop the history rather than guess
            end
            entry[#entry + 1] = { l, before, after }
        end
        out[#out + 1] = entry
    end
    return out
end

function HoshiGame.deserialize(t)
    if type(t) ~= "table" or t.version ~= 1 then return nil end
    local n = tonumber(t.size)
    if not n or n < 2 or n > 12 or type(t.clues) ~= "table" or #t.clues ~= n * n then return nil end
    local clues = {}
    for i = 1, n * n do
        local c = tonumber(t.clues[i]) or -1
        if c < 0 or c > 8 then return nil end
        clues[i] = c
    end
    local g = setmetatable({}, HoshiGame)
    setup(g, n, clues)
    if #g.P.islands == 0 then return nil end
    g.difficulty = LEVELS[t.difficulty] and t.difficulty or "medium"

    -- the answer must still be one, or the save is no good
    g.solution = cleanList(t.solution)
    local answer = g.solution and hoshi.fromList(g.P, g.solution)
    if not (answer and hoshi.check(g.P, answer)) then return nil end

    -- the player's bridges: dropped if they don't fit the board
    local list = cleanList(t.bridges)
    local counts = list and hoshi.fromList(g.P, list)
    if counts then
        for l = 1, #g.P.links do
            if counts[l] > g.P.links[l].max then counts = nil break end
            if counts[l] > 0 then
                for _, m in ipairs(g.P.crosses[l]) do
                    if counts[m] > 0 then counts = nil break end
                end
            end
            if not counts then break end
        end
    end
    if counts then g.counts = counts end

    g.elapsed = tonumber(t.elapsed) or 0
    local cursor = tonumber(t.cursor)
    g.cursor = (cursor and g.P.index[cursor]) and cursor or middleIsland(g.P)
    g.undoStack = counts and cleanStack(t.undoStack, #g.P.links) or {}
    g.redoStack = counts and cleanStack(t.redoStack, #g.P.links) or {}
    for _, stack in ipairs({ g.undoStack, g.redoStack }) do
        for _, e in ipairs(stack) do
            if not g.P.index[e.at] then e.at = g.cursor end
        end
    end
    g.solved = g:isSolved()
    return g
end

return HoshiGame
