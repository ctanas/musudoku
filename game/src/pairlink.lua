-- Pairlink engine: solving, generating and grading puzzles.
-- Pure Lua, no LÖVE dependency, so it can be unit-tested with plain `luajit`.
--
-- The rules: join each pair of matching numbers with a line that runs from
-- cell to cell, side by side. Lines never cross or branch, never pass
-- through a number, and together they use every cell.
--
-- A puzzle of size n is a flat array of n*n clues (index 1 = top-left,
-- row-major): 0 for an empty cell, or k for an end of pair k. A solution is
-- a list of lines, one per pair: lines[k] lists the cells from one end of
-- pair k to the other.

local bit = require("bit")
local band, bor, lshift = bit.band, bit.bor, bit.lshift

local M = {}

M.SIZES = { 7, 8, 9 }
M.DIFFICULTIES = { "easy", "medium", "hard" }

-- What the solver knows about each edge (the link between two cells side by
-- side): not yet, part of a line, or not part of any line.
local UNKNOWN, ON, OFF = 0, 1, 2

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

local function reverse(list)
    local i, j = 1, #list
    while i < j do
        list[i], list[j] = list[j], list[i]
        i, j = i + 1, j - 1
    end
end

-- Board geometry per size, built on first use: each cell's neighbours, and
-- the edges between them (ea[e] and eb[e] are an edge's two cells,
-- cellEdges[i] the edges of cell i, edgeAt[i][j] the edge between i and j).
local geometries = {}

local function geometry(n)
    local g = geometries[n]
    if g then return g end
    g = { n = n, count = n * n, nbrs = {}, ea = {}, eb = {}, cellEdges = {}, edgeAt = {} }
    for i = 1, n * n do
        local r, c = math.floor((i - 1) / n), (i - 1) % n
        local list = {}
        if r > 0 then list[#list + 1] = i - n end
        if c > 0 then list[#list + 1] = i - 1 end
        if c < n - 1 then list[#list + 1] = i + 1 end
        if r < n - 1 then list[#list + 1] = i + n end
        g.nbrs[i] = list
        g.cellEdges[i], g.edgeAt[i] = {}, {}
    end
    local function add(a, b)
        local e = #g.ea + 1
        g.ea[e], g.eb[e] = a, b
        table.insert(g.cellEdges[a], e)
        table.insert(g.cellEdges[b], e)
        g.edgeAt[a][b], g.edgeAt[b][a] = e, e
    end
    for i = 1, n * n do
        local r, c = math.floor((i - 1) / n), (i - 1) % n
        if c < n - 1 then add(i, i + 1) end
        if r < n - 1 then add(i, i + n) end
    end
    g.edges = #g.ea
    geometries[n] = g
    return g
end
M.geometry = geometry

-- The two ends of each pair: ends[k] = { a, b }, or nil if a number doesn't
-- appear exactly twice.
function M.ends(n, clues)
    local ends, pairs = {}, 0
    for i = 1, n * n do
        local k = clues[i]
        if k ~= 0 then
            if not ends[k] then
                ends[k] = { i }
                pairs = math.max(pairs, k)
            elseif #ends[k] == 1 then
                ends[k][2] = i
            else
                return nil
            end
        end
    end
    for k = 1, pairs do
        if not ends[k] or #ends[k] ~= 2 then return nil end
    end
    return ends, pairs
end

-- True if `lines` solves the puzzle: line k runs side by side from one end
-- of pair k to the other, no cell is used twice or is another pair's number,
-- and every cell is used.
function M.check(n, clues, lines)
    local g = geometry(n)
    local ends, pairs = M.ends(n, clues)
    if not ends or #lines ~= pairs then return false end
    local used = {}
    for k = 1, pairs do
        local line = lines[k]
        if #line < 2 then return false end
        local a, b = line[1], line[#line]
        if not ((a == ends[k][1] and b == ends[k][2]) or (a == ends[k][2] and b == ends[k][1])) then
            return false
        end
        for s, i in ipairs(line) do
            if used[i] then return false end
            used[i] = true
            if s > 1 and not g.edgeAt[line[s - 1]][i] then return false end
            if s > 1 and s < #line and clues[i] ~= 0 then return false end
        end
    end
    for i = 1, g.count do
        if not used[i] then return false end
    end
    return true
end

-- Solver ----------------------------------------------------------------------
-- Works on edges, the way a person reasons about where lines can go, and
-- reports the hardest technique needed:
--   1  the basics: a number has one line out and any other cell two, so a
--      cell with only that many ways out uses them all, and a cell that has
--      them closes the rest; a link that would close a loop, or join lines
--      from two different pairs, is ruled out
--   2  + reach: a cell that only one pair's line can still reach belongs to
--      that pair, and two cells side by side that no pair's line can both
--      reach aren't linked
--   3  + trying a line's next step and finding that it breaks a rule
-- Every step is sound, so a board this solves completely has exactly one
-- solution.

-- Tables for one puzzle: need[i] is how many line links cell i has (1 for a
-- number, 2 otherwise).
local function prepare(n, clues)
    local ends, pairs = M.ends(n, clues)
    if not ends then return nil end
    local g = geometry(n)
    local need = {}
    for i = 1, g.count do need[i] = (clues[i] ~= 0) and 1 or 2 end
    return { n = n, g = g, clues = clues, ends = ends, pairs = pairs, need = need }
end

-- Union-find over cells joined by ON edges ("fragments" of lines).
local parent, rootLabel, root = {}, {}, {}

local function find(x)
    while parent[x] ~= x do
        parent[x] = parent[parent[x]]
        x = parent[x]
    end
    return x
end

-- Joins cells along ON edges into fragments, fills root[i] with each cell's
-- fragment and spreads each fragment's pair to all its cells. Returns false
-- if the lines close a loop or two pairs' lines meet.
local function fragments(P, es, lab)
    local g = P.g
    for i = 1, g.count do parent[i] = i end
    for e = 1, g.edges do
        if es[e] == ON then
            local ra, rb = find(g.ea[e]), find(g.eb[e])
            if ra == rb then return false end
            parent[ra] = rb
        end
    end
    for i = 1, g.count do rootLabel[i] = 0 end
    for i = 1, g.count do
        local r = find(i)
        root[i] = r
        local l = lab[i]
        if l ~= 0 then
            local f = rootLabel[r]
            if f ~= 0 and f ~= l then return false end
            rootLabel[r] = l
        end
    end
    for i = 1, g.count do lab[i] = rootLabel[root[i]] end
    return true
end

-- Technique 1 until it decides nothing more. es holds the edges' states,
-- lab each cell's pair (0 while unknown). Returns false on a broken rule.
local function basics(P, es, lab)
    local g, need = P.g, P.need
    local changed = true
    while changed do
        changed = false
        for i = 1, g.count do
            local on, unknown = 0, 0
            for _, e in ipairs(g.cellEdges[i]) do
                local s = es[e]
                if s == ON then on = on + 1 elseif s == UNKNOWN then unknown = unknown + 1 end
            end
            local want = need[i]
            if on > want or on + unknown < want then return false end
            if unknown > 0 and (on == want or on + unknown == want) then
                local s = (on == want) and OFF or ON
                for _, e in ipairs(g.cellEdges[i]) do
                    if es[e] == UNKNOWN then es[e] = s end
                end
                changed = true
            end
        end
        if not fragments(P, es, lab) then return false end
        for e = 1, g.edges do
            if es[e] == UNKNOWN then
                local a, b = g.ea[e], g.eb[e]
                if root[a] == root[b] or (lab[a] ~= 0 and lab[b] ~= 0 and lab[a] ~= lab[b]) then
                    es[e] = OFF
                    changed = true
                end
            end
        end
    end
    return true
end

-- Technique 2. From one end of each pair, walks every link not ruled out,
-- through cells that are free or already that pair's (never on through a
-- number). The pair's other end must be reached, and so must every cell
-- already known to be that pair's. A free cell no pair reaches breaks the
-- rules; one only a single pair reaches is that pair's. A link between two
-- cells that no one pair reaches both of is ruled out (tracked as bit masks
-- of pairs, so only for up to 31 pairs). Returns ok, progress.
local queue, seen, stamp = {}, {}, 0
local reachCount, reachBy, reachMask = {}, {}, {}

local function reach(P, es, lab)
    local g, clues = P.g, P.clues
    for i = 1, g.count do reachCount[i], reachBy[i], reachMask[i] = 0, 0, 0 end
    local masks = P.pairs <= 31
    for k = 1, P.pairs do
        local a, b = P.ends[k][1], P.ends[k][2]
        stamp = stamp + 1
        local head, tail = 1, 1
        queue[1] = a
        seen[a] = stamp
        while head <= tail do
            local i = queue[head]
            head = head + 1
            if i == a or clues[i] == 0 then
                for _, e in ipairs(g.cellEdges[i]) do
                    if es[e] ~= OFF then
                        local j = (g.ea[e] == i) and g.eb[e] or g.ea[e]
                        local l = lab[j]
                        if seen[j] ~= stamp and (l == 0 or l == k) then
                            seen[j] = stamp
                            tail = tail + 1
                            queue[tail] = j
                        end
                    end
                end
            end
        end
        if seen[b] ~= stamp then return false end
        local kbit = masks and lshift(1, k - 1) or 0
        for i = 1, g.count do
            if seen[i] == stamp then
                reachCount[i] = reachCount[i] + 1
                reachBy[i] = k
                reachMask[i] = bor(reachMask[i], kbit)
            elseif lab[i] == k then
                return false
            end
        end
    end
    local progress = false
    for i = 1, g.count do
        if lab[i] == 0 then
            if reachCount[i] == 0 then return false end
            if reachCount[i] == 1 then
                lab[i] = reachBy[i]
                progress = true
            end
        end
    end
    if masks then
        for e = 1, g.edges do
            if es[e] == UNKNOWN and band(reachMask[g.ea[e]], reachMask[g.eb[e]]) == 0 then
                es[e] = OFF
                progress = true
            end
        end
    end
    return true, progress
end

-- Techniques 1 and 2 until they decide nothing more. False on a broken rule.
local function settle(P, es, lab)
    while true do
        if not basics(P, es, lab) then return false end
        local ok, progress = reach(P, es, lab)
        if not ok then return false end
        if not progress then return true end
    end
end

-- Technique 3: at the open end of a line (a number with no link yet, or a
-- line's last cell), try a link as the next step and settle. If that breaks
-- a rule, the link is ruled out. Returns true if it ruled one out.
local tryList = {}

local function trial(P, es, lab, yield)
    local g, n = P.g, 0
    for i = 1, g.count do
        local on, unknown = 0, 0
        for _, e in ipairs(g.cellEdges[i]) do
            local s = es[e]
            if s == ON then on = on + 1 elseif s == UNKNOWN then unknown = unknown + 1 end
        end
        if unknown > 0 and (P.clues[i] ~= 0 or on == 1) and on < P.need[i] then
            for _, e in ipairs(g.cellEdges[i]) do
                if es[e] == UNKNOWN then
                    n = n + 1
                    tryList[n] = e
                end
            end
        end
    end
    for k = 1, n do
        local e = tryList[k]
        if es[e] == UNKNOWN then
            local tes, tlab = copy(es), copy(lab)
            tes[e] = ON
            if not settle(P, tes, tlab) then
                es[e] = OFF
                return true
            end
            if yield then yield() end
        end
    end
    return false
end

-- Follows ON edges from each pair's first end to its other end.
local function linesFrom(P, es)
    local g, lines = P.g, {}
    for k = 1, P.pairs do
        local line, prev, i = { P.ends[k][1] }, nil, P.ends[k][1]
        while i ~= P.ends[k][2] do
            local nextCell
            for _, e in ipairs(g.cellEdges[i]) do
                if es[e] == ON then
                    local j = (g.ea[e] == i) and g.eb[e] or g.ea[e]
                    if j ~= prev then nextCell = j end
                end
            end
            prev, i = i, nextCell
            line[#line + 1] = i
        end
        lines[k] = line
    end
    return lines
end

-- Returns the hardest technique used (1 to 3) and the solution lines. If
-- techniques up to maxLevel (default 3) don't finish it, returns nil and,
-- when it got stuck rather than finding no solution, the edges' states.
function M.solve(n, clues, maxLevel, yield)
    maxLevel = maxLevel or 3
    local P = prepare(n, clues)
    if not P then return nil end
    local es, lab = {}, {}
    for e = 1, P.g.edges do es[e] = UNKNOWN end
    for i = 1, P.g.count do lab[i] = clues[i] end
    local level = 1
    while true do
        if not basics(P, es, lab) then return nil end
        local done = true
        for e = 1, P.g.edges do
            if es[e] == UNKNOWN then
                done = false
                break
            end
        end
        if done then return level, linesFrom(P, es) end
        local ok, progress = true, false
        if maxLevel >= 2 then ok, progress = reach(P, es, lab) end
        if not ok then return nil end
        if progress then
            level = math.max(level, 2)
        elseif maxLevel >= 3 and trial(P, es, lab, yield) then
            level = 3
        else
            return nil, es
        end
    end
end

-- Generator -------------------------------------------------------------------
-- Covers the board with many short random lines, each at least three cells
-- long, whose ends become pairs of numbers. If the basics can't solve that
-- yet, a line by an undecided link is cut in two, which gives them more to
-- go on. Then, the way a Sudoku is dug out, neighbouring lines are joined one
-- at a time (one pair fewer each), keeping a join only while the solver can
-- still finish the puzzle at the wanted level. Joins are checked with the
-- easiest techniques first, which are the quickest. The solver finishing
-- proves the puzzle has exactly one solution: the lines it was built from.

M.LEVELS = { easy = 1, medium = 2, hard = 3 }

-- Average line length to start from (longer means fewer pairs, but more cuts
-- before the basics can solve it), and attempts before settling for the
-- closest level.
M.START_LENGTH = 6
local ATTEMPTS = 12
-- How each level digs: in turn, { techniques allowed, tries at moving line
-- ends around }. Each try is a solve, and technique 3's are the slowest.
-- Medium digs only part of the way with the basics, or there'd be little
-- left for reach to add; hard skips reach for the same reason. Hard digs
-- far with the basics first, which is quick and leaves the slow technique
-- less to do.
M.PHASES = {
    { { 1, 400 } },
    { { 1, 100 }, { 2, 300 } },
    { { 1, 800 }, { 3, 15 } },
}

-- At most this many pairs, so every number is one digit. A puzzle with more
-- after digging gets up to EXTRA more rounds at its own level (with these
-- many tries at moving ends per level), and is dropped if that isn't enough.
M.MAX_PAIRS = 9
local EXTRA = 3
M.EXTRA_SHIFTS = { 150, 150, 10 }

local function lineIndex(line, cell)
    for s, i in ipairs(line) do
        if i == cell then return s end
    end
end

-- About `target` random lines covering every cell, each at least three and
-- (mostly) at most maxLen cells long, as a list of cell lists. Nil if the
-- short lines couldn't be fixed.
local function coverBoard(n, rng, target, maxLen)
    local g = geometry(n)
    local lineOf, lines = {}, {}
    for i = 1, g.count do
        lineOf[i] = i
        lines[i] = { i }
    end
    local alive = g.count
    local order = {}
    for e = 1, g.edges do order[e] = e end

    local function isEnd(line, i) return line[1] == i or line[#line] == i end
    -- Joins the lines through the ends a and b, side by side.
    local function join(a, b)
        local la, lb = lineOf[a], lineOf[b]
        local A, B = lines[la], lines[lb]
        if A[#A] ~= a then reverse(A) end
        if B[1] ~= b then reverse(B) end
        for _, i in ipairs(B) do
            A[#A + 1] = i
            lineOf[i] = la
        end
        lines[lb] = nil
        alive = alive - 1
    end

    local joined = true
    while alive > target and joined do
        joined = false
        shuffle(order, rng)
        for _, e in ipairs(order) do
            if alive <= target then break end
            local a, b = g.ea[e], g.eb[e]
            local A, B = lines[lineOf[a]], lines[lineOf[b]]
            if A ~= B and isEnd(A, a) and isEnd(B, b) and #A + #B <= maxLen then
                join(a, b)
                joined = true
            end
        end
    end

    -- Short lines: join a neighbouring line's end, or take over the part of
    -- a neighbouring line beyond the cell next to them.
    local function fixShort(id)
        local S = lines[id]
        local cellsAround = { S[1], S[#S] }
        for _, s in ipairs(cellsAround) do
            local nbrs = shuffle(copy(g.nbrs[s]), rng)
            for _, t in ipairs(nbrs) do
                local T = lines[lineOf[t]]
                if T ~= S and isEnd(T, t) then
                    if S[#S] ~= s then reverse(S) end
                    join(s, t)
                    return true
                end
            end
            for _, t in ipairs(nbrs) do
                local tid = lineOf[t]
                local T = lines[tid]
                if T ~= S then
                    local k = lineIndex(T, t)
                    local keep, take
                    if k - 1 >= 3 then
                        keep, take = { unpack(T, 1, k - 1) }, { unpack(T, k) }
                    elseif #T - k >= 3 then
                        keep, take = { unpack(T, k + 1) }, { unpack(T, 1, k) }
                        reverse(take)
                    end
                    if keep then
                        lines[tid] = keep
                        if S[#S] ~= s then reverse(S) end
                        for _, i in ipairs(take) do
                            S[#S + 1] = i
                            lineOf[i] = id
                        end
                        return true
                    end
                end
            end
        end
        return false
    end

    local fixing = true
    while fixing do
        fixing = false
        for id, line in pairs(lines) do
            if #line < 3 then
                if not fixShort(id) then return nil end
                fixing = true
                break
            end
        end
    end

    local out = {}
    for _, line in pairs(lines) do out[#out + 1] = line end
    table.sort(out, function(a, b) return a[1] < b[1] end) -- pairs() order isn't fixed
    return shuffle(out, rng)
end

local function cluesOf(n, lines)
    local clues = {}
    for i = 1, n * n do clues[i] = 0 end
    for k, line in ipairs(lines) do
        clues[line[1]], clues[line[#line]] = k, k
    end
    return clues
end

-- Cuts a line next to an undecided link in two, each part at least three
-- cells long. False if no line there can be cut.
local function cutNear(n, lines, es, rng)
    local g = geometry(n)
    local undecided = {}
    for e = 1, g.edges do
        if es[e] == UNKNOWN then undecided[#undecided + 1] = e end
    end
    shuffle(undecided, rng)
    for _, e in ipairs(undecided) do
        for _, cell in ipairs({ g.ea[e], g.eb[e] }) do
            for id, line in ipairs(lines) do
                local k = lineIndex(line, cell)
                if k then
                    -- the cut between cells j and j + 1 nearest to the cell
                    for d = 0, #line do
                        for _, j in ipairs({ k - d, k + d - 1 }) do
                            if j >= 3 and #line - j >= 3 then
                                lines[id] = { unpack(line, 1, j) }
                                lines[#lines + 1] = { unpack(line, j + 1) }
                                return true
                            end
                        end
                    end
                    break
                end
            end
        end
    end
    return false
end

-- The lines with line la (through its end a) and line lb (through its end
-- b) joined into one, a and b being side by side.
local function joinLines(lines, la, a, lb, b)
    local A, B = copy(lines[la]), copy(lines[lb])
    if A[#A] ~= a then reverse(A) end
    if B[1] ~= b then reverse(B) end
    for _, i in ipairs(B) do A[#A + 1] = i end
    local out = {}
    for k, line in ipairs(lines) do
        if k == la then out[#out + 1] = A elseif k ~= lb then out[#out + 1] = line end
    end
    return out
end

-- A random line's end takes over the part of the line beside it from the
-- cell next to the end onwards; the other part (at least three cells) stays.
-- The number of pairs stays the same, but the ends move, so lines that
-- couldn't be joined may now be. Returns the new lines and the two ends that
-- changed, or nil if the picked end can't do that.
local function shiftLines(n, lines, rng)
    local g = geometry(n)
    local la = rng(#lines)
    local A = copy(lines[la])
    if rng(2) == 1 then reverse(A) end
    local a = A[#A]
    local nbrs = g.nbrs[a]
    local t = nbrs[rng(#nbrs)]
    for lb, B in ipairs(lines) do
        local k = lineIndex(B, t)
        if k then
            if lb == la or k == 1 or k == #B then return nil end
            local keep, take
            local first = k - 1 >= 3
            local second = #B - k >= 3
            if first and second then
                if rng(2) == 1 then second = false else first = false end
            end
            if first then
                keep, take = { unpack(B, 1, k - 1) }, { unpack(B, k) }
            elseif second then
                keep, take = { unpack(B, k + 1) }, { unpack(B, 1, k) }
                reverse(take)
            else
                return nil
            end
            for _, i in ipairs(take) do A[#A + 1] = i end
            local out = {}
            for m, line in ipairs(lines) do
                if m == la then out[#out + 1] = A elseif m == lb then out[#out + 1] = keep else out[#out + 1] = line end
            end
            return out, { A[#A], first and keep[#keep] or keep[1] }
        end
    end
end

-- Tries joining every two lines whose ends are side by side, in random
-- order, keeping each join the solver can still finish at `level`. With
-- `around` (a list of cells), only joins at those cells.
local function joinAll(n, lines, level, rng, yield, around)
    local g = geometry(n)
    local order = {}
    if around then
        for _, i in ipairs(around) do
            for _, e in ipairs(g.cellEdges[i]) do order[#order + 1] = e end
        end
    else
        for e = 1, g.edges do order[e] = e end
    end
    shuffle(order, rng)
    for _, e in ipairs(order) do
        local a, b = g.ea[e], g.eb[e]
        local la, lb
        for k, line in ipairs(lines) do
            if line[1] == a or line[#line] == a then la = k end
            if line[1] == b or line[#line] == b then lb = k end
        end
        if la and lb and la ~= lb then
            local candidate = joinLines(lines, la, a, lb, b)
            if M.solve(n, cluesOf(n, candidate), level, yield) then lines = candidate end
            if yield then yield() end
        end
    end
    return lines
end

-- Joins lines while the solver can still finish the puzzle at `level`, and
-- with `shifts`, also moves line ends around (keeping it solvable) to find
-- more joins. After a move, only joins at the ends that moved are tried:
-- the others were tried already.
local function dig(n, lines, level, rng, yield, shifts)
    lines = joinAll(n, lines, level, rng, yield)
    for _ = 1, shifts do
        local candidate, moved = shiftLines(n, lines, rng)
        if candidate and M.solve(n, cluesOf(n, candidate), level, yield) then
            lines = joinAll(n, candidate, level, rng, yield, moved)
        end
        if yield then yield() end
    end
    return lines
end

-- Numbers in reading order: pair 1 is the one whose first end comes first.
local function sortLines(lines)
    table.sort(lines, function(a, b) return math.min(a[1], a[#a]) < math.min(b[1], b[#b]) end)
end

-- Returns { size, clues, lines, pairs, level }. `yield` (optional) is called
-- regularly so a caller can spread the work over several frames.
function M.generate(n, difficulty, rng, yield)
    rng = rng or defaultRng
    local want = M.LEVELS[difficulty] or 2
    local count = n * n
    local best, bestScore
    local attempts = 0
    while true do
        local lines = coverBoard(n, rng, math.floor(count / M.START_LENGTH), 2 * M.START_LENGTH)
        while lines do
            local level, stuck = M.solve(n, cluesOf(n, lines), 1, yield)
            if level then break end
            if not stuck or not cutNear(n, lines, stuck, rng) then lines = nil end
        end
        if lines then
            attempts = attempts + 1
            for _, phase in ipairs(M.PHASES[want]) do
                lines = dig(n, lines, phase[1], rng, yield, phase[2])
            end
            for _ = 1, EXTRA do
                if #lines <= M.MAX_PAIRS then break end
                lines = dig(n, lines, want, rng, yield, M.EXTRA_SHIFTS[want])
            end
            if #lines <= M.MAX_PAIRS then
                sortLines(lines)
                local clues = cluesOf(n, lines)
                local level, solved = M.solve(n, clues, want)
                local result = { size = n, clues = clues, lines = solved, pairs = #lines, level = level }
                local score = want - level
                if score == 0 then return result end
                if not best or score < bestScore then best, bestScore = result, score end
            end
        end
        if best and attempts >= ATTEMPTS then return best end
    end
end

return M
