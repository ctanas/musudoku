-- Hoshi engine: solving, generating and grading puzzles.
-- Pure Lua, no LÖVE dependency, so it can be unit-tested with plain `luajit`.
--
-- The rules (a Hashiwokakero-style puzzle): islands, the cells with a
-- number, are joined by bridges that run straight across the water along a
-- row or column. Two islands have at most two bridges between them. An
-- island's number is how many bridges end at it, bridges never cross each
-- other or an island, and together they connect every island.
--
-- A puzzle of size n is a flat array of n*n clues (index 1 = top-left,
-- row-major): 0 for water, or an island's number (1 to 8). Two islands that
-- see each other along a row or column, with only water between, can be
-- joined: that's a link. A solution gives each link 0, 1 or 2 bridges.

local M = {}

M.SIZES = { 7, 9 }
M.DIFFICULTIES = { "easy", "medium", "hard" }
M.LEVELS = { easy = 1, medium = 2, hard = 3 }

M.DIRS = { up = { -1, 0 }, down = { 1, 0 }, left = { 0, -1 }, right = { 0, 1 } }
local DIR_LIST = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }


local function copy(t)
    local out = {}
    for i = 1, #t do out[i] = t[i] end
    return out
end

local function defaultRng(n) return math.random(n) end

-- Structure ---------------------------------------------------------------------

-- Everything about a puzzle that doesn't change while it's solved:
--   islands[k]    the cell of island k, in reading order; index[cell] = k
--   links[l]      { a, b, horizontal, cells, max }: islands a and b (cells,
--                 a above or left of b), the water cells between them, and
--                 the most bridges the link can take
--   linksOf[k]    the links of island k
--   toward[cell]  [direction] = the link leaving that island that way
--   crosses[l]    the links that cross link l
function M.analyze(n, clues)
    local P = { n = n, clues = clues, islands = {}, index = {}, links = {}, linksOf = {}, toward = {} }
    for i = 1, n * n do
        if clues[i] ~= 0 then
            local k = #P.islands + 1
            P.islands[k], P.index[i] = i, k
            P.linksOf[k], P.toward[i] = {}, {}
        end
    end
    local across, down = {}, {} -- [cell] = the link passing over it
    local function add(a, b, horizontal, cells)
        local l = #P.links + 1
        P.links[l] = {
            a = a, b = b, horizontal = horizontal, cells = cells,
            max = math.min(2, clues[a], clues[b]),
        }
        table.insert(P.linksOf[P.index[a]], l)
        table.insert(P.linksOf[P.index[b]], l)
        if horizontal then
            P.toward[a].right, P.toward[b].left = l, l
        else
            P.toward[a].down, P.toward[b].up = l, l
        end
        for _, c in ipairs(cells) do
            if horizontal then across[c] = l else down[c] = l end
        end
    end
    for _, a in ipairs(P.islands) do
        local r, c = math.floor((a - 1) / n), (a - 1) % n
        local cells = {}
        for cc = c + 1, n - 1 do
            local j = r * n + cc + 1
            if clues[j] ~= 0 then
                add(a, j, true, cells)
                break
            end
            cells[#cells + 1] = j
        end
        cells = {}
        for rr = r + 1, n - 1 do
            local j = rr * n + c + 1
            if clues[j] ~= 0 then
                add(a, j, false, cells)
                break
            end
            cells[#cells + 1] = j
        end
    end
    P.crosses = {}
    for l = 1, #P.links do P.crosses[l] = {} end
    for i = 1, n * n do
        local h, v = across[i], down[i]
        if h and v then
            table.insert(P.crosses[h], v)
            table.insert(P.crosses[v], h)
        end
    end
    return P
end

-- The link between the islands at cells a and b, or nil.
function M.linkBetween(P, a, b)
    for _, dir in pairs(P.toward[a] or {}) do
        local link = P.links[dir]
        if (link.a == a and link.b == b) or (link.a == b and link.b == a) then return dir end
    end
end

-- True if the islands are all joined through links that `usable(l)` allows.
local function connected(P, usable)
    local count = #P.islands
    if count == 0 then return false end
    local seen, stack, reached = { [1] = true }, { 1 }, 1
    while #stack > 0 do
        local k = table.remove(stack)
        for _, l in ipairs(P.linksOf[k]) do
            if usable(l) then
                local link = P.links[l]
                local j = P.index[link.a] == k and P.index[link.b] or P.index[link.a]
                if not seen[j] then
                    seen[j] = true
                    reached = reached + 1
                    stack[#stack + 1] = j
                end
            end
        end
    end
    return reached == count
end

-- True if counts[l] (0, 1 or 2 bridges per link) solves the puzzle: every
-- island has its number of bridges, no two bridges cross, and every island
-- is connected.
function M.check(P, counts)
    local sum = {}
    for k = 1, #P.islands do sum[k] = 0 end
    for l, link in ipairs(P.links) do
        local c = counts[l] or 0
        if c < 0 or c > 2 then return false end
        if c > 0 then
            for _, m in ipairs(P.crosses[l]) do
                if (counts[m] or 0) > 0 then return false end
            end
            local ka, kb = P.index[link.a], P.index[link.b]
            sum[ka], sum[kb] = sum[ka] + c, sum[kb] + c
        end
    end
    for k, i in ipairs(P.islands) do
        if sum[k] ~= P.clues[i] then return false end
    end
    return connected(P, function(l) return (counts[l] or 0) > 0 end)
end

-- Solutions travel as lists of { a, b, count } (island cells), which don't
-- depend on how links are numbered.
function M.toList(P, counts)
    local out = {}
    for l, link in ipairs(P.links) do
        if (counts[l] or 0) > 0 then out[#out + 1] = { link.a, link.b, counts[l] } end
    end
    return out
end

-- Counts per link from such a list, or nil if a bridge isn't a link.
function M.fromList(P, list)
    local counts = {}
    for l = 1, #P.links do counts[l] = 0 end
    for _, e in ipairs(list) do
        local l = M.linkBetween(P, e[1], e[2])
        if not l or (e[3] ~= 1 and e[3] ~= 2) then return nil end
        counts[l] = e[3]
    end
    return counts
end

-- Solver ----------------------------------------------------------------------
-- Works on each link's lowest and highest possible bridge count, the way a
-- person reasons about an island, and reports the hardest technique needed:
--   1  counting: an island needs its number of bridges, so if its other
--      links can't make up the rest, a link must have some; if they already
--      have most of them, a link can't have more. A bridge rules out the
--      links it would cross
--   2  + connecting: a bridge that would close off a group of islands that
--      can't take any more bridges is ruled out, and a group with only one
--      way out must take it
--   3  + trying a link's lowest or highest count and finding that it breaks
--      a rule
-- Every step is sound, so a puzzle this solves completely has exactly one
-- solution.

-- Technique 1 until it decides nothing more. False on a broken rule.
local function counting(P, lo, hi)
    local clues = P.clues
    local changed = true
    while changed do
        changed = false
        for k, i in ipairs(P.islands) do
            local need = clues[i]
            local sumLo, sumHi = 0, 0
            for _, l in ipairs(P.linksOf[k]) do
                sumLo, sumHi = sumLo + lo[l], sumHi + hi[l]
            end
            if sumLo > need or sumHi < need then return false end
            for _, l in ipairs(P.linksOf[k]) do
                local newLo = math.max(lo[l], need - (sumHi - hi[l]))
                local newHi = math.min(hi[l], need - (sumLo - lo[l]))
                if newLo > newHi then return false end
                if newLo ~= lo[l] or newHi ~= hi[l] then
                    sumLo, sumHi = sumLo + newLo - lo[l], sumHi + newHi - hi[l]
                    lo[l], hi[l] = newLo, newHi
                    changed = true
                end
            end
        end
        for l = 1, #P.links do
            if lo[l] > 0 then
                for _, m in ipairs(P.crosses[l]) do
                    if hi[m] > 0 then
                        if lo[m] > 0 then return false end
                        hi[m] = 0
                        changed = true
                    end
                end
            end
        end
    end
    return true
end

-- Technique 2, one pass. Groups are islands joined by bridges known to be
-- there (lo > 0); a group's need is the bridges its islands still lack. A
-- group that needs none is closed: it can't connect to anything else.
-- Returns ok, progress.
local parent = {}

local function find(x)
    while parent[x] ~= x do
        parent[x] = parent[parent[x]]
        x = parent[x]
    end
    return x
end

local function connecting(P, lo, hi)
    local count = #P.islands
    for k = 1, count do parent[k] = k end
    for l, link in ipairs(P.links) do
        if lo[l] > 0 then
            local ra, rb = find(P.index[link.a]), find(P.index[link.b])
            if ra ~= rb then parent[ra] = rb end
        end
    end
    local need, size = {}, {}
    for k, i in ipairs(P.islands) do
        local r = find(k)
        local missing = P.clues[i]
        for _, l in ipairs(P.linksOf[k]) do missing = missing - lo[l] end
        need[r] = (need[r] or 0) + missing
        size[r] = (size[r] or 0) + 1
    end
    if size[find(1)] == count then return true, false end -- one group: nothing to connect
    for k = 1, count do
        if parent[k] == k and need[k] == 0 then return false end -- closed off from the rest
    end
    if not connected(P, function(l) return hi[l] > 0 end) then return false end

    local progress = false
    for l, link in ipairs(P.links) do
        if lo[l] < hi[l] then
            local ra, rb = find(P.index[link.a]), find(P.index[link.b])
            if ra == rb then
                -- one more bridge inside a group that needs only two closes it
                if need[ra] == 2 then
                    hi[l] = lo[l]
                    progress = true
                end
            elseif size[ra] + size[rb] < count then
                -- joining two groups with as many bridges as they need closes both
                local together = need[ra] + need[rb]
                if together == 2 then
                    hi[l] = 0
                    progress = true
                elseif together == 4 and hi[l] == 2 then
                    hi[l] = 1
                    progress = true
                end
            end
        end
    end

    -- a group with only one link out must use it
    local exits, exit = {}, {}
    for l, link in ipairs(P.links) do
        if hi[l] > 0 then
            local ra, rb = find(P.index[link.a]), find(P.index[link.b])
            if ra ~= rb then
                exits[ra], exit[ra] = (exits[ra] or 0) + 1, l
                exits[rb], exit[rb] = (exits[rb] or 0) + 1, l
            end
        end
    end
    for k = 1, count do
        if parent[k] == k then
            if not exits[k] then return false end
            local l = exit[k]
            if exits[k] == 1 and lo[l] == 0 then
                lo[l] = 1
                progress = true
            end
        end
    end
    return true, progress
end

-- Techniques 1 and 2 until they decide nothing more. False on a broken rule.
local function settle(P, lo, hi)
    while true do
        if not counting(P, lo, hi) then return false end
        local ok, progress = connecting(P, lo, hi)
        if not ok then return false end
        if not progress then return true end
    end
end

-- Technique 3: give an open link its lowest or its highest count and settle.
-- If that breaks a rule, the link can't have that count. Returns true if it
-- ruled one out.
local function trial(P, lo, hi, yield)
    for l = 1, #P.links do
        if lo[l] < hi[l] then
            for _, v in ipairs({ lo[l], hi[l] }) do
                local tlo, thi = copy(lo), copy(hi)
                tlo[l], thi[l] = v, v
                if not settle(P, tlo, thi) then
                    if v == lo[l] then lo[l] = v + 1 else hi[l] = v - 1 end
                    return true
                end
                if yield then yield() end
            end
        end
    end
    return false
end

-- Returns the hardest technique used (1 to 3) and the bridges per link. If
-- techniques up to maxLevel (default 3) don't finish it, returns nil.
-- `puzzle` is an analyze() result, or n with `clues`.
function M.solve(puzzle, clues, maxLevel, yield)
    local P = type(puzzle) == "table" and puzzle or M.analyze(puzzle, clues)
    maxLevel = maxLevel or 3
    if #P.islands == 0 then return nil end
    local lo, hi = {}, {}
    for l, link in ipairs(P.links) do lo[l], hi[l] = 0, link.max end
    local level = 1
    while true do
        if not counting(P, lo, hi) then return nil end
        local done = true
        for l = 1, #P.links do
            if lo[l] ~= hi[l] then
                done = false
                break
            end
        end
        if done then
            if M.check(P, lo) then return level, lo end
            return nil
        end
        local ok, progress = true, false
        if maxLevel >= 2 then ok, progress = connecting(P, lo, hi) end
        if not ok then return nil end
        if progress then
            level = math.max(level, 2)
        elseif maxLevel >= 3 and trial(P, lo, hi, yield) then
            level = 3
        else
            return nil
        end
    end
end

-- Generator -------------------------------------------------------------------
-- Builds the answer first: an island, then island after island, each
-- placed across the water from one already there and joined to it with one
-- or two bridges, never over a bridge or right beside another island. Then
-- extra bridges join some islands that already see each other, which makes
-- loops. The numbers are each island's bridges, so every puzzle has at least
-- this solution. A puzzle is kept only if the solver finishes it at the
-- wanted level, which proves the solution is the only one.

-- Islands per cell of the board, and the chance (in %) of a double bridge
-- and of an extra bridge between islands that see each other, per level.
-- Double bridges give a lot away (an island with few links and a big number
-- is quickly settled), so easy puzzles have many and the others few. Too
-- many extra bridges make loops that can be built more than one way, and
-- those puzzles are dropped. With these, about half the answers come out
-- easy, over half medium, and a few in a hundred hard.
M.DENSITY = 0.25
M.DOUBLE = { 50, 5, 15 }
M.EXTRA = { 25, 15, 15 }
local MISSES = 300    -- failed tries at placing an island before stopping
local ATTEMPTS = 400  -- answers tried before settling for the closest level

-- Clues for a random answer, or nil if too few islands fit.
local function randomAnswer(n, rng, target, double, extra)
    local count = n * n
    local island, water = {}, {} -- water[c]: a bridge passes over cell c
    local islands = {}
    local bridges = {}

    local function nearIsland(i)
        local r, c = math.floor((i - 1) / n), (i - 1) % n
        for _, d in ipairs(DIR_LIST) do
            local rr, cc = r + d[1], c + d[2]
            if rr >= 0 and rr < n and cc >= 0 and cc < n and island[rr * n + cc + 1] then return true end
        end
        return false
    end

    -- the cells a bridge from a could reach going (dr, dc): free water, at
    -- least one cell away, and not beside another island
    local function reachable(a, d)
        local r, c = math.floor((a - 1) / n), (a - 1) % n
        local cells, options = {}, {}
        r, c = r + d[1], c + d[2]
        while r >= 0 and r < n and c >= 0 and c < n do
            local j = r * n + c + 1
            if island[j] or water[j] then break end
            if #cells >= 1 and not nearIsland(j) then options[#options + 1] = { j, #cells } end
            cells[#cells + 1] = j
            r, c = r + d[1], c + d[2]
        end
        return cells, options
    end

    local first = rng(count)
    island[first] = true
    islands[1] = first
    local misses = 0
    while #islands < target and misses < MISSES do
        local a = islands[rng(#islands)]
        local cells, options = reachable(a, DIR_LIST[rng(4)])
        if #options == 0 then
            misses = misses + 1
        else
            local pick = options[rng(#options)]
            local b, between = pick[1], pick[2]
            island[b] = true
            islands[#islands + 1] = b
            for s = 1, between do water[cells[s]] = true end
            bridges[#bridges + 1] = { a, b, rng(100) <= double and 2 or 1 }
        end
    end
    if #islands < target * 0.75 then return nil end

    -- extra bridges between islands that see each other over free water
    local marks = {}
    for i = 1, count do marks[i] = island[i] and 1 or 0 end
    local P = M.analyze(n, marks)
    local joined = {}
    for _, b in ipairs(bridges) do joined[math.min(b[1], b[2]) .. ":" .. math.max(b[1], b[2])] = true end
    for _, link in ipairs(P.links) do
        if not joined[link.a .. ":" .. link.b] and #link.cells >= 1 and rng(100) <= extra then
            local free = true
            for _, c in ipairs(link.cells) do
                if water[c] then free = false end
            end
            if free then
                for _, c in ipairs(link.cells) do water[c] = true end
                bridges[#bridges + 1] = { link.a, link.b, rng(100) <= double and 2 or 1 }
            end
        end
    end

    local clues = {}
    for i = 1, count do clues[i] = 0 end
    for _, b in ipairs(bridges) do
        clues[b[1]] = clues[b[1]] + b[3]
        clues[b[2]] = clues[b[2]] + b[3]
    end
    return clues
end

-- Returns { size, clues, bridges, islands, level }: bridges is the solution
-- as a list of { a, b, count }. `yield` (optional) is called regularly so a
-- caller can spread the work over several frames.
function M.generate(n, difficulty, rng, yield)
    rng = rng or defaultRng
    local want = M.LEVELS[difficulty] or 2
    local target = math.floor(n * n * M.DENSITY + 0.5)
    local best, bestScore
    local attempts = 0
    while true do
        local clues = randomAnswer(n, rng, target, M.DOUBLE[want], M.EXTRA[want])
        if clues then
            attempts = attempts + 1
            local P = M.analyze(n, clues)
            local level, counts = M.solve(P, nil, want, yield)
            if level then
                local result = {
                    size = n, clues = clues, bridges = M.toList(P, counts),
                    islands = #P.islands, level = level,
                }
                if level == want then return result end
                local score = want - level
                if not best or score < bestScore then best, bestScore = result, score end
            end
        end
        if yield then yield() end
        if best and attempts >= ATTEMPTS then return best end
    end
end


return M
