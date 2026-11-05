-- Run from the repository root:  luajit tests/test_hoshi.lua [puzzles-per-level]
-- Hoshi engine: the puzzle structure, the rules check, the solver and the
-- generator. Every generated puzzle must have a solution, and only one:
-- they're also counted by brute force, independently of the solver and of
-- the engine's own idea of which islands can be joined.
package.path = "./game/?.lua;" .. package.path
local hoshi = require("src.hoshi")

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

-- Counts solutions (up to 2) by trying 0, 1 or 2 bridges on every pair of
-- islands that see each other, found here from scratch. It prunes only what
-- can't be finished: an island past its number, or one that can no longer
-- reach it, and bridges that cross.
local function bruteCount(n, clues)
    local islands, at = {}, {}
    for i = 1, n * n do
        if clues[i] ~= 0 then
            islands[#islands + 1] = i
            at[i] = #islands
        end
    end
    local links = {} -- { a, b, cells }
    for _, a in ipairs(islands) do
        local r, c = math.floor((a - 1) / n), (a - 1) % n
        for _, d in ipairs({ { 0, 1 }, { 1, 0 } }) do
            local cells, rr, cc = {}, r + d[1], c + d[2]
            while rr < n and cc < n do
                local j = rr * n + cc + 1
                if clues[j] ~= 0 then
                    links[#links + 1] = { at[a], at[j], cells }
                    break
                end
                cells[#cells + 1] = j
                rr, cc = rr + d[1], cc + d[2]
            end
        end
    end
    local over = {} -- [cell] = link over it
    local sum, left = {}, {} -- bridges so far, and the most the undecided links could add
    for k = 1, #islands do sum[k], left[k] = 0, 0 end
    for _, link in ipairs(links) do
        left[link[1]] = left[link[1]] + 2
        left[link[2]] = left[link[2]] + 2
    end
    local count, value = 0, {}

    local function connectedAll()
        local seen, stack, reached = { [1] = true }, { 1 }, 1
        while #stack > 0 do
            local k = table.remove(stack)
            for l, link in ipairs(links) do
                if value[l] > 0 and (link[1] == k or link[2] == k) then
                    local j = link[1] == k and link[2] or link[1]
                    if not seen[j] then
                        seen[j] = true
                        reached = reached + 1
                        stack[#stack + 1] = j
                    end
                end
            end
        end
        return reached == #islands
    end

    local function go(l)
        if count >= 2 then return end
        if l > #links then
            for k, i in ipairs(islands) do
                if sum[k] ~= clues[i] then return end
            end
            if connectedAll() then count = count + 1 end
            return
        end
        local a, b, cells = links[l][1], links[l][2], links[l]
        cells = cells[3]
        left[a], left[b] = left[a] - 2, left[b] - 2
        for v = 0, 2 do
            local ok = sum[a] + v <= clues[islands[a]] and sum[b] + v <= clues[islands[b]]
                and sum[a] + v + left[a] >= clues[islands[a]] and sum[b] + v + left[b] >= clues[islands[b]]
            if ok and v > 0 then
                for _, c in ipairs(cells) do
                    if over[c] then ok = false end
                end
            end
            if ok then
                value[l] = v
                sum[a], sum[b] = sum[a] + v, sum[b] + v
                if v > 0 then for _, c in ipairs(cells) do over[c] = l end end
                go(l + 1)
                if v > 0 then for _, c in ipairs(cells) do over[c] = nil end end
                sum[a], sum[b] = sum[a] - v, sum[b] - v
            end
        end
        value[l] = nil
        left[a], left[b] = left[a] + 2, left[b] + 2
    end
    go(1)
    return count
end

-- Structure -----------------------------------------------------------------

-- A square of four islands: a double bridge along the top, singles down
-- both sides, none along the bottom.
local square = parse([[
3 . 3
. . .
1 . 1
]])
local P = hoshi.analyze(3, square)
check("four islands", #P.islands == 4)
check("four links", #P.links == 4)
check("toward", P.toward[1].right and P.toward[3].left == P.toward[1].right and P.toward[1].down)
check("link max follows the numbers", P.links[P.toward[7].right].max == 1 and P.links[P.toward[1].right].max == 2)
check("link between", hoshi.linkBetween(P, 3, 1) == P.toward[1].right and not hoshi.linkBetween(P, 1, 9))
check("no crossings", #P.crosses[1] == 0)

local answer = hoshi.fromList(P, { { 1, 3, 2 }, { 1, 7, 1 }, { 3, 9, 1 } })
check("answer from a list", answer ~= nil)
check("answer passes", hoshi.check(P, answer))
local wrong = hoshi.fromList(P, { { 1, 3, 1 }, { 1, 7, 2 }, { 3, 9, 2 } })
check("wrong counts fail", not hoshi.check(P, wrong))
check("list for a non-link", hoshi.fromList(P, { { 1, 9, 1 } }) == nil)
local back = hoshi.toList(P, answer)
check("to a list and back", #back == 3 and hoshi.check(P, hoshi.fromList(P, back)))

local level, solved = hoshi.solve(3, square)
check("square solves by counting", level == 1 and hoshi.check(P, solved))
check("square has one solution", bruteCount(3, square) == 1)

-- Crossing links: a column and a row through the middle cell.
local cross = parse([[
. 1 .
1 . 1
. 1 .
]])
local C = hoshi.analyze(3, cross)
check("crossing links", #C.links == 2 and #C.crosses[1] == 1 and C.crosses[1][1] == 2)
check("crossing bridges fail", not hoshi.check(C, { 1, 1 }))
check("unsolvable: they'd have to cross", hoshi.solve(3, cross) == nil and bruteCount(3, cross) == 0)

-- Two pairs of 1s, each pair joined, but the pairs apart: no solution.
local apart = parse([[
1 . 1
. . .
1 . 1
]])
check("disconnected answer isn't a solution", hoshi.solve(3, apart) == nil and bruteCount(3, apart) == 0)

-- A row: each end needs its one bridge, which is all the middle needs.
local chain = parse([[
1 . 2 . 1
. . . . .
. . . . .
. . . . .
. . . . .
]])
check("chain solves by counting", hoshi.solve(5, chain) == 1 and bruteCount(5, chain) == 1)

-- Four 2s in a square: two doubles would make two pairs cut off from each
-- other, so it takes connecting to see they're all single.
local ring = parse([[
2 . 2
. . .
2 . 2
]])
local ringLevel, ringAnswer = hoshi.solve(3, ring)
check("ring needs connecting", ringLevel == 2, ringLevel)
check("ring is all singles", ringAnswer and ringAnswer[1] == 1 and ringAnswer[2] == 1
    and ringAnswer[3] == 1 and ringAnswer[4] == 1)
check("ring has one solution", bruteCount(3, ring) == 1)
check("counting alone can't finish the ring", hoshi.solve(3, ring, 1) == nil)

-- Four 3s in a square: the doubles can go top and bottom or left and right,
-- so there are two solutions, and the solver doesn't finish it.
local loop = parse([[
3 . 3
. . .
3 . 3
]])
check("ambiguous loop counts two", bruteCount(3, loop) == 2)
check("solver doesn't finish an ambiguous loop", hoshi.solve(3, loop) == nil)

-- Generator -------------------------------------------------------------------

local per = tonumber(arg and arg[1]) or 8
math.randomseed(5)
local function rng(n) return math.random(n) end

for _, n in ipairs(hoshi.SIZES) do
    for _, d in ipairs(hoshi.DIFFICULTIES) do
        local onLevel, worst, total = 0, 0, 0
        for s = 1, per do
            local t0 = os.clock()
            local g = hoshi.generate(n, d, rng)
            local dt = os.clock() - t0
            worst, total = math.max(worst, dt), total + dt
            local name = string.format("%dx%d %s #%d", n, n, d, s)
            local GP = hoshi.analyze(n, g.clues)
            local counts = hoshi.fromList(GP, g.bridges)
            check(name .. " answer is a solution", counts and hoshi.check(GP, counts))
            check(name .. " has exactly one solution", bruteCount(n, g.clues) == 1)
            local level = hoshi.solve(GP, nil, 3)
            check(name .. " solver agrees on the level", level == g.level, tostring(level) .. " vs " .. tostring(g.level))
            local islands = 0
            for i = 1, n * n do
                local c = g.clues[i]
                if c ~= 0 then
                    islands = islands + 1
                    check(name .. " numbers 1 to 8", c >= 1 and c <= 8, c)
                end
            end
            local target = math.floor(n * n * hoshi.DENSITY + 0.5)
            check(name .. " island count", islands == g.islands and islands >= target * 0.75, islands)
            -- no two islands side by side
            for i = 1, n * n do
                if g.clues[i] ~= 0 then
                    local c = (i - 1) % n
                    local beside = (c < n - 1 and g.clues[i + 1] ~= 0) or (i + n <= n * n and g.clues[i + n] ~= 0)
                    check(name .. " islands apart", not beside, i)
                end
            end
            if g.level == hoshi.LEVELS[d] then onLevel = onLevel + 1 end
        end
        print(string.format("%dx%d %-6s %d of %d on level, avg %.1f ms, worst %.1f ms",
            n, n, d, onLevel, per, total * 1000 / per, worst * 1000))
        check(string.format("%dx%d %s mostly on level", n, n, d), onLevel >= per * 0.75, onLevel)
    end
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
