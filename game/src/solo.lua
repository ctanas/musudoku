-- Solo engine: solving, generating and grading puzzles.
-- Pure Lua, no LÖVE dependency, so it can be unit-tested with plain `luajit`.
--
-- The rules: shade cells so that no number shows twice, unshaded, in a row
-- or column. Shaded cells never touch side by side, and the unshaded cells
-- stay connected side by side. As usual for this kind of puzzle, a cell is
-- only shaded to remove a repeat: each shaded number still shows, unshaded,
-- somewhere in its row or column. Without that, extra shading could be added
-- to almost any solution, and no puzzle would have just one.
--
-- A puzzle of size n is a flat array of n*n numbers from 1 to n (index 1 =
-- top-left, row-major). Solver states and solutions hold UNKNOWN, SHADED or
-- KEPT (unshaded) per cell.

local M = {}

M.SIZES = { 5, 7, 9 }
M.DIFFICULTIES = { "easy", "medium", "hard" }

local UNKNOWN, SHADED, KEPT = 0, 1, 2
M.UNKNOWN, M.SHADED, M.KEPT = UNKNOWN, SHADED, KEPT

-- Helpers ---------------------------------------------------------------------

local function copy(t)
    local out = {}
    for i = 1, #t do out[i] = t[i] end
    return out
end
M.copy = copy

local function defaultRng(n) return math.random(n) end

local function shuffle(list, rng)
    for i = #list, 2, -1 do
        local j = rng(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

-- Board geometry per size, built on first use: each cell's neighbours side
-- by side, and the rows and columns as lists of cells ("lines").
local geometries = {}

local function geometry(n)
    local g = geometries[n]
    if g then return g end
    g = { n = n, count = n * n, nbrs = {}, lines = {} }
    for i = 1, n * n do
        local r, c = math.floor((i - 1) / n), (i - 1) % n
        local list = {}
        if r > 0 then list[#list + 1] = i - n end
        if c > 0 then list[#list + 1] = i - 1 end
        if c < n - 1 then list[#list + 1] = i + 1 end
        if r < n - 1 then list[#list + 1] = i + n end
        g.nbrs[i] = list
    end
    for k = 0, n - 1 do
        local row, col = {}, {}
        for j = 0, n - 1 do
            row[#row + 1] = k * n + j + 1
            col[#col + 1] = j * n + k + 1
        end
        g.lines[#g.lines + 1] = row
        g.lines[#g.lines + 1] = col
    end
    geometries[n] = g
    return g
end
M.geometry = geometry

-- Breadth-first search from `start` through cells that aren't SHADED (and
-- aren't `skip`). Returns how many KEPT cells it reached.
local queue, seen, stamp = {}, {}, 0

local function keptReached(g, st, start, skip)
    stamp = stamp + 1
    local head, tail, kept = 1, 1, 0
    queue[1] = start
    seen[start] = stamp
    while head <= tail do
        local i = queue[head]
        head = head + 1
        if st[i] == KEPT then kept = kept + 1 end
        for _, j in ipairs(g.nbrs[i]) do
            if seen[j] ~= stamp and j ~= skip and st[j] ~= SHADED then
                seen[j] = stamp
                tail = tail + 1
                queue[tail] = j
            end
        end
    end
    return kept
end

-- True if `shaded` (shaded[i] = true for shaded cells) keeps the rules: no
-- number repeats unshaded in a line, no shaded cells touch, and the unshaded
-- cells are connected. The game accepts any shading that does.
function M.check(n, values, shaded)
    local g = geometry(n)
    for _, line in ipairs(g.lines) do
        local used = {}
        for _, i in ipairs(line) do
            if not shaded[i] then
                if used[values[i]] then return false end
                used[values[i]] = true
            end
        end
    end
    local st, kept, start = {}, 0, nil
    for i = 1, g.count do
        if shaded[i] then
            st[i] = SHADED
            for _, j in ipairs(g.nbrs[i]) do
                if shaded[j] then return false end
            end
        else
            st[i] = KEPT
            kept = kept + 1
            start = start or i
        end
    end
    return start ~= nil and keptReached(g, st, start) == kept
end

-- Solver ----------------------------------------------------------------------
-- Solves the way a person would and reports the hardest technique needed:
--   1  the basics: a number with no repeat in its row or column stays; a cell
--      beside a shaded cell stays; a kept number's repeats in its row and
--      column are shaded; in x y x the y stays; and with x x side by side,
--      every other x in that line is shaded
--   2  + connection: a cell whose shading would cut the unshaded cells in
--      two stays
--   3  + trying a cell one way and finding that it breaks a rule
-- Every step is sound, so a board this solves completely has exactly one
-- solution.

-- Tables for one puzzle: repeats[i] lists the cells in i's row and column
-- with the same number, and `forced` holds { cell, state } for the cells the
-- basics decide from the numbers alone.
local function prepare(n, values)
    local g = geometry(n)
    local repeats = {}
    for i = 1, g.count do repeats[i] = {} end
    for _, line in ipairs(g.lines) do
        for a = 1, n do
            for b = 1, n do
                if a ~= b and values[line[a]] == values[line[b]] then
                    local list = repeats[line[a]]
                    list[#list + 1] = line[b]
                end
            end
        end
    end
    local forced = {}
    for i = 1, g.count do
        if #repeats[i] == 0 then forced[#forced + 1] = { i, KEPT } end
    end
    for _, line in ipairs(g.lines) do
        for k = 1, n - 2 do
            if values[line[k]] == values[line[k + 2]] then forced[#forced + 1] = { line[k + 1], KEPT } end
        end
        for k = 1, n - 1 do
            local v = values[line[k]]
            if values[line[k + 1]] == v then
                for m = 1, n do
                    if m ~= k and m ~= k + 1 and values[line[m]] == v then
                        forced[#forced + 1] = { line[m], SHADED }
                    end
                end
            end
        end
    end
    return { n = n, g = g, values = values, repeats = repeats, forced = forced }
end

-- Technique 1 until it decides nothing more. Returns false if the board
-- breaks a rule.
local function basics(P, st)
    local nbrs, repeats = P.g.nbrs, P.repeats
    local changed = true
    while changed do
        changed = false
        for i = 1, P.g.count do
            local s = st[i]
            if s == SHADED then
                for _, j in ipairs(nbrs[i]) do
                    local t = st[j]
                    if t == SHADED then return false end
                    if t == UNKNOWN then
                        st[j] = KEPT
                        changed = true
                    end
                end
            elseif s == KEPT then
                for _, j in ipairs(repeats[i]) do
                    local t = st[j]
                    if t == KEPT then return false end
                    if t == UNKNOWN then
                        st[j] = SHADED
                        changed = true
                    end
                end
            end
        end
    end
    return true
end

-- The rules basics() doesn't check: the kept cells can still connect (through
-- cells that aren't shaded), and every shaded number still has a repeat
-- that isn't shaded.
local function consistent(P, st)
    local kept, start = 0, nil
    for i = 1, P.g.count do
        local s = st[i]
        if s == KEPT then
            kept = kept + 1
            start = start or i
        elseif s == SHADED then
            local needed = false
            for _, j in ipairs(P.repeats[i]) do
                if st[j] ~= SHADED then
                    needed = true
                    break
                end
            end
            if not needed then return false end
        end
    end
    return start == nil or keptReached(P.g, st, start) == kept
end

-- Technique 2. Returns true if it decided a cell.
local function connection(P, st)
    local kept, start = 0, nil
    for i = 1, P.g.count do
        if st[i] == KEPT then
            kept = kept + 1
            start = start or i
        end
    end
    if not start then return false end
    local progress = false
    for i = 1, P.g.count do
        if st[i] == UNKNOWN and keptReached(P.g, st, start, i) < kept then
            st[i] = KEPT
            kept = kept + 1
            progress = true
        end
    end
    return progress
end

-- Techniques 1 and 2 until they decide nothing more. False on a broken rule.
local function settle(P, st)
    repeat
        if not basics(P, st) or not consistent(P, st) then return false end
    until not connection(P, st)
    return true
end

-- Technique 3: shade an unknown cell (then keep it) and settle. If that
-- breaks a rule, the cell must be the other way. Returns true if it decided
-- a cell.
local function trial(P, st, yield)
    for i = 1, P.g.count do
        if st[i] == UNKNOWN then
            local t = copy(st)
            t[i] = SHADED
            if not settle(P, t) then
                st[i] = KEPT
                return true
            end
            t = copy(st)
            t[i] = KEPT
            if not settle(P, t) then
                st[i] = SHADED
                return true
            end
            if yield then yield() end
        end
    end
    return false
end

-- Returns the hardest technique used (1 to 3) and the solution as a list of
-- states, or nil if techniques up to maxLevel (default 3) don't finish it.
function M.solve(n, values, maxLevel, yield)
    maxLevel = maxLevel or 3
    local P = prepare(n, values)
    local st = {}
    for i = 1, P.g.count do st[i] = UNKNOWN end
    for _, f in ipairs(P.forced) do
        local i, s = f[1], f[2]
        if st[i] ~= UNKNOWN and st[i] ~= s then return nil end
        st[i] = s
    end
    local level = 1
    while true do
        if not basics(P, st) or not consistent(P, st) then return nil end
        local done = true
        for i = 1, P.g.count do
            if st[i] == UNKNOWN then
                done = false
                break
            end
        end
        if done then return level, st end
        if maxLevel >= 2 and connection(P, st) then
            level = math.max(level, 2)
        elseif maxLevel >= 3 and trial(P, st, yield) then
            level = 3
        else
            return nil
        end
    end
end

-- Generator -------------------------------------------------------------------
-- Makes a random Latin square (each number once per row and column), shades
-- random cells that don't touch while keeping the rest connected, and gives
-- each shaded cell the number of an unshaded cell in its row or column. The
-- solver then has to finish it at the wanted level, which also proves its
-- solution is the only one.

M.LEVELS = { easy = 1, medium = 2, hard = 3 }

-- Share of cells to shade (the most that fit without touching or cutting
-- the board in two is usually a little less, about 29%), and attempts per
-- level before settling for the closest one. On 9x9, only about one random
-- puzzle in a hundred is easy, so easy gets the most attempts.
local DENSITY = 0.32
local ATTEMPTS = { 1000, 300, 300 }

-- Fills cell by cell with random numbers, backing up at dead ends.
local function latinSquare(n, rng)
    local grid, rowUsed, colUsed = {}, {}, {}
    for k = 0, n - 1 do rowUsed[k], colUsed[k] = {}, {} end
    local function fill(i)
        if i > n * n then return true end
        local r, c = math.floor((i - 1) / n), (i - 1) % n
        local options = {}
        for v = 1, n do
            if not rowUsed[r][v] and not colUsed[c][v] then options[#options + 1] = v end
        end
        shuffle(options, rng)
        for _, v in ipairs(options) do
            grid[i], rowUsed[r][v], colUsed[c][v] = v, true, true
            if fill(i + 1) then return true end
            rowUsed[r][v], colUsed[c][v] = nil, nil
        end
        grid[i] = nil
        return false
    end
    fill(1)
    return grid
end

-- States with about `density` of the cells shaded, none touching, and the
-- unshaded cells connected.
local function shadeCells(n, rng, density)
    local g = geometry(n)
    local st, order = {}, {}
    for i = 1, g.count do
        st[i] = KEPT
        order[i] = i
    end
    shuffle(order, rng)
    local target = math.floor(g.count * density + 0.5)
    local shaded, kept = 0, g.count
    for _, i in ipairs(order) do
        if shaded >= target then break end
        local free = true
        for _, j in ipairs(g.nbrs[i]) do
            if st[j] == SHADED then
                free = false
                break
            end
        end
        if free then
            st[i] = SHADED
            local start = 1
            while st[start] ~= KEPT do start = start + 1 end
            if keptReached(g, st, start) == kept - 1 then
                shaded, kept = shaded + 1, kept - 1
            else
                st[i] = KEPT
            end
        end
    end
    return st
end

local function makePuzzle(n, rng, density)
    local latin = latinSquare(n, rng)
    local st = shadeCells(n, rng, density)
    local values = copy(latin)
    for i = 1, n * n do
        if st[i] == SHADED then
            local r, c, choices = math.floor((i - 1) / n), (i - 1) % n, {}
            for k = 0, n - 1 do
                local a, b = r * n + k + 1, k * n + c + 1
                if st[a] == KEPT then choices[#choices + 1] = latin[a] end
                if st[b] == KEPT then choices[#choices + 1] = latin[b] end
            end
            values[i] = choices[rng(#choices)]
        end
    end
    return values
end

-- Returns { size, values, solution, level }. `yield` (optional) is called
-- regularly so a caller can spread the work over several frames.
function M.generate(n, difficulty, rng, yield)
    rng = rng or defaultRng
    local want = M.LEVELS[difficulty] or 2
    local best, bestScore
    local attempts = 0
    while true do
        attempts = attempts + 1
        local values = makePuzzle(n, rng, DENSITY)
        local level, solution = M.solve(n, values, 3, yield)
        if yield then yield() end
        if level then
            local result = { size = n, values = values, solution = solution, level = level }
            local score = math.abs(level - want)
            if score == 0 then return result end
            if not best or score < bestScore then best, bestScore = result, score end
        end
        if best and attempts >= ATTEMPTS[want] then return best end
    end
end

return M
