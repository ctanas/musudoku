-- Run from the repository root:  luajit tests/test_pairlink.lua [puzzles-per-level]
-- Pairlink engine: the rules check, the solver and the generator. Every
-- generated puzzle must have a solution, and only one: 7x7 boards are also
-- counted by brute force, independently of the solver.
package.path = "./game/?.lua;" .. package.path
local pairlink = require("src.pairlink")

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

local function parse(s)
    local t = {}
    for ch in s:gmatch("[%d%.]") do t[#t + 1] = (ch == ".") and 0 or tonumber(ch) end
    return t
end

-- Counts solutions (up to 2) by drawing each pair's line in turn, cell by
-- cell, independent of the solver. It only prunes what can't be finished: a
-- free cell without two ways in, a pair whose ends can no longer meet, or
-- free cells no unfinished line can reach.
local function bruteCount(n, clues)
    local g = pairlink.geometry(n)
    local ends, pairs = pairlink.ends(n, clues)
    local N = n * n
    local owner = {}
    for i = 1, N do owner[i] = clues[i] end
    local count = 0

    -- cells an unfinished line can still link into: free cells, the active
    -- head, and the ends of pairs not yet joined
    local function open(i, k, head)
        if owner[i] == 0 or i == head then return true end
        local c = clues[i]
        return c ~= 0 and c >= k and i ~= ends[k][1]
    end

    local function feasible(k, head)
        for i = 1, N do
            if owner[i] == 0 then
                local ways = 0
                for _, j in ipairs(g.nbrs[i]) do
                    if open(j, k, head) then ways = ways + 1 end
                end
                if ways < 2 then return false end
            end
        end
        local reached = {}
        for m = k, pairs do
            local from, to = (m == k) and head or ends[m][1], ends[m][2]
            local seen, stack, met = { [from] = true }, { from }, false
            while #stack > 0 do
                local i = table.remove(stack)
                for _, j in ipairs(g.nbrs[i]) do
                    if j == to then met = true end
                    if owner[j] == 0 and not seen[j] then
                        seen[j] = true
                        reached[j] = true
                        stack[#stack + 1] = j
                    end
                end
            end
            if not met then return false end
        end
        for i = 1, N do
            if owner[i] == 0 and not reached[i] then return false end
        end
        return true
    end

    local function go(k, head)
        if count >= 2 then return end
        if k > pairs then
            for i = 1, N do
                if owner[i] == 0 then return end
            end
            count = count + 1
            return
        end
        for _, j in ipairs(g.nbrs[head]) do
            if j == ends[k][2] then
                if k == pairs then go(k + 1, nil)
                elseif feasible(k + 1, ends[k + 1][1]) then go(k + 1, ends[k + 1][1]) end
            elseif owner[j] == 0 then
                owner[j] = k
                if feasible(k, j) then go(k, j) end
                owner[j] = 0
            end
        end
    end
    if feasible(1, ends[1][1]) then go(1, ends[1][1]) end
    return count
end

-- The rules check
local rows4 = parse([[
1..1
2..2
3..3
4..4]])
local straight = { { 1, 2, 3, 4 }, { 5, 6, 7, 8 }, { 9, 10, 11, 12 }, { 13, 14, 15, 16 } }
check("straight lines solve it", pairlink.check(4, rows4, straight))
local gap = { { 1, 2, 3, 4 }, { 5, 6, 7, 8 }, { 9, 10, 11, 12 }, { 13, 16 } }
check("a jump between cells breaks the rules", not pairlink.check(4, rows4, gap))
local emptyRow = parse([[
1..1
....
2..2
3..3]])
local skipping = { { 1, 2, 3, 4 }, { 9, 10, 11, 12 }, { 13, 14, 15, 16 } }
check("unused cells break the rules", not pairlink.check(4, emptyRow, skipping))
local through = { { 1, 2, 6, 7, 3, 4 }, { 5, 6, 7, 8 }, { 9, 10, 11, 12 }, { 13, 14, 15, 16 } }
check("a cell used twice breaks the rules", not pairlink.check(4, rows4, through))
local threeOnes = parse([[
1.11
2..2
3..3
4..4]])
check("three of a number isn't a puzzle", pairlink.ends(4, threeOnes) == nil)

-- One solution: the four straight rows
local level, lines = pairlink.solve(4, rows4)
check("rows puzzle solves", level ~= nil)
check("rows puzzle solution keeps the rules", lines and pairlink.check(4, rows4, lines))
check("rows puzzle grades easy", level == 1, level)
check("rows puzzle unique by brute force", bruteCount(4, rows4) == 1)

-- No solution: the lines would have to cross
local crossing = parse([[
12
21]])
check("crossing puzzle doesn't solve", pairlink.solve(2, crossing) == nil)
check("crossing puzzle has no solution by brute force", bruteCount(2, crossing) == 0)

-- Generator
math.randomseed(tonumber(os.getenv("SEED") or "") or os.time())
local function rng(n) return math.random(n) end
local per = tonumber(arg and arg[1]) or 5
for _, n in ipairs(pairlink.SIZES) do
    for _, diff in ipairs(pairlink.DIFFICULTIES) do
        local t0 = os.clock()
        local levels, onTarget, pairTotal, slowest = {}, 0, 0, 0
        for _ = 1, per do
            local p0 = os.clock()
            local r = pairlink.generate(n, diff, rng)
            slowest = math.max(slowest, os.clock() - p0)
            local name = n .. "x" .. n .. " " .. diff
            check(name .. " solution keeps the rules", pairlink.check(n, r.clues, r.lines))
            local again = pairlink.solve(n, r.clues)
            check(name .. " solves again at the same level", again == r.level)
            local shortest = math.huge
            for _, line in ipairs(r.lines) do shortest = math.min(shortest, #line) end
            check(name .. " lines are at least 3 cells", shortest >= 3, shortest)
            check(name .. " at most 9 pairs (one digit each)", r.pairs <= pairlink.MAX_PAIRS, r.pairs)
            if n == 7 then
                check(name .. " has exactly one solution (brute force)", bruteCount(n, r.clues) == 1)
            end
            levels[#levels + 1] = r.level
            pairTotal = pairTotal + r.pairs
            if r.level == pairlink.LEVELS[diff] then onTarget = onTarget + 1 end
        end
        local ms = (os.clock() - t0) * 1000 / per
        print(string.format("%dx%d %-6s avg %7.1f ms  max %6.0f ms  pairs %4.1f  on-target %d/%d  levels %s",
            n, n, diff, ms, slowest * 1000, pairTotal / per, onTarget, per, table.concat(levels, ",")))
    end
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
