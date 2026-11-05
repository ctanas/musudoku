-- Run from the repository root:  luajit tests/test_solo.lua [puzzles-per-level]
-- Solo engine: the rules check, the solver and the generator. Every
-- generated puzzle must have a solution, and only one: small boards are
-- also counted by brute force, independently of the solver.
package.path = "./game/?.lua;" .. package.path
local solo = require("src.solo")

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

local function parse(s)
    local t = {}
    for ch in s:gmatch("%d") do t[#t + 1] = tonumber(ch) end
    return t
end

local function shadedOf(states)
    local out = {}
    for i, s in ipairs(states) do out[i] = (s == solo.SHADED) end
    return out
end

-- Counts solutions (up to 2) by trying every shading, independent of the
-- solver's techniques: shaded cells don't touch, no number repeats unshaded
-- in a line, the unshaded cells connect, and every shaded number repeats an
-- unshaded one in its row or column.
local function bruteCount(n, values)
    local N = n * n
    local shaded = {}
    local count = 0
    local function lineOk(i)
        -- the row and column of cell i, as far as they're decided (cells < i)
        local r, c = math.floor((i - 1) / n), (i - 1) % n
        local v = values[i]
        for k = 0, n - 1 do
            local a, b = r * n + k + 1, k * n + c + 1
            if a < i and not shaded[a] and values[a] == v then return false end
            if b < i and not shaded[b] and values[b] == v then return false end
        end
        return true
    end
    local function finished()
        for i = 1, N do
            if shaded[i] then
                local r, c, needed = math.floor((i - 1) / n), (i - 1) % n, false
                for k = 0, n - 1 do
                    local a, b = r * n + k + 1, k * n + c + 1
                    if (a ~= i and not shaded[a] and values[a] == values[i])
                        or (b ~= i and not shaded[b] and values[b] == values[i]) then
                        needed = true
                    end
                end
                if not needed then return false end
            end
        end
        return solo.check(n, values, shaded)
    end
    local function go(i)
        if count >= 2 then return end
        if i > N then
            if finished() then count = count + 1 end
            return
        end
        local r, c = math.floor((i - 1) / n), (i - 1) % n
        -- shaded
        if not (c > 0 and shaded[i - 1]) and not (r > 0 and shaded[i - n]) then
            shaded[i] = true
            go(i + 1)
            shaded[i] = false
        end
        -- unshaded
        if lineOk(i) then go(i + 1) end
    end
    go(1)
    return count
end

-- The rules check
local values5 = parse([[
12345
23451
34512
45123
51234]])
local none = {}
check("a Latin square needs no shading", solo.check(5, values5, none))
local touching = { [1] = true, [2] = true }
check("touching shaded cells break the rules", not solo.check(5, values5, touching))
local walled = { [2] = true, [6] = true }
check("a cut-off corner breaks the rules", not solo.check(5, values5, walled))
local repeat5 = solo.copy(values5)
repeat5[2] = 1 -- 1 1 3 4 5 on the top row
check("an unshaded repeat breaks the rules", not solo.check(5, repeat5, none))
check("shading the repeat fixes it", solo.check(5, repeat5, { [2] = true }))

-- Two solutions: shade the repeat, or keep it and shade both 1s it repeats
check("two solutions don't solve", solo.solve(5, repeat5) == nil)
check("two solutions by brute force", bruteCount(5, repeat5) == 2)

-- The corner: keeping the top-left 2 would shade both its neighbours and cut
-- it off, so it's the one shaded. Found by trying it (technique 3).
local corner = solo.copy(values5)
corner[1] = 2
local level, states = solo.solve(5, corner)
check("corner puzzle solves", level ~= nil)
check("corner puzzle grades hard", level == 3, level)
local onlyCorner = states ~= nil
for i = 1, 25 do
    if states and (states[i] == solo.SHADED) ~= (i == 1) then onlyCorner = false end
end
check("corner puzzle shades only the corner", onlyCorner)
check("corner puzzle unique by brute force", bruteCount(5, corner) == 1)

-- No solution: of four 1s side by side, three would need shading, and two
-- of those would touch
local bad = parse([[
11115
23451
34512
45123
51234]])
check("impossible puzzle doesn't solve", solo.solve(5, bad) == nil)
check("impossible puzzle has no solution by brute force", bruteCount(5, bad) == 0)

-- Generator
math.randomseed(tonumber(os.getenv("SEED") or "") or os.time())
local function rng(n) return math.random(n) end
local per = tonumber(arg and arg[1]) or 5
for _, n in ipairs(solo.SIZES) do
    for _, diff in ipairs(solo.DIFFICULTIES) do
        local t0 = os.clock()
        local levels, onTarget, shadedTotal = {}, 0, 0
        for _ = 1, per do
            local r = solo.generate(n, diff, rng)
            local name = n .. "x" .. n .. " " .. diff
            local shaded = shadedOf(r.solution)
            check(name .. " solution keeps the rules", solo.check(n, r.values, shaded))
            local again = solo.solve(n, r.values)
            check(name .. " solves again at the same level", again == r.level)
            local inRange = true
            for i = 1, n * n do
                if r.values[i] < 1 or r.values[i] > n then inRange = false end
                if shaded[i] then shadedTotal = shadedTotal + 1 end
            end
            check(name .. " numbers are 1 to n", inRange)
            if n <= 7 then
                check(name .. " has exactly one solution (brute force)", bruteCount(n, r.values) == 1)
            end
            levels[#levels + 1] = r.level
            if r.level == solo.LEVELS[diff] then onTarget = onTarget + 1 end
        end
        local ms = (os.clock() - t0) * 1000 / per
        print(string.format("%dx%d %-6s avg %6.1f ms  shaded %4.1f%%  on-target %d/%d  levels %s",
            n, n, diff, ms, 100 * shadedTotal / (per * n * n), onTarget, per, table.concat(levels, ",")))
    end
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
