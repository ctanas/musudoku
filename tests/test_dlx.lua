-- Run from the repository root:  luajit tests/test_dlx.lua [puzzles-per-difficulty]
-- Dancing Links solver and the generator that uses it, checked against the
-- backtracking solver in sudoku.lua.
package.path = "./game/?.lua;" .. package.path

local sudoku = require("src.sudoku")
local dlx = require("src.dlx")

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL  " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

local function parse(s)
    local g = {}
    for ch in s:gmatch("[%d%.]") do g[#g + 1] = (ch == ".") and 0 or tonumber(ch) end
    assert(#g == 81, "bad grid literal")
    return g
end

local function same(a, b)
    for i = 1, 81 do if a[i] ~= b[i] then return false end end
    return true
end

local classic = parse([[
53..7....
6..195...
.98....6.
8...6...3
4..8.3..1
7...2...6
.6....28.
...419..5
....8..79]])

local count, solution = dlx.solve(classic, 2)
check("classic puzzle unique", count == 1, "count " .. tostring(count))
local _, expected = sudoku.solve(classic, 2)
check("same solution as backtracking", solution and same(solution, expected))

local inkala = parse([[
8........
..36.....
.7..9.2..
.5...7...
....457..
...1...3.
..1....68
..85...1.
.9....4..]])
check("Inkala unique", dlx.countSolutions(inkala, 2) == 1)

local empty = {}
for i = 1, 81 do empty[i] = 0 end
check("empty grid has many solutions", dlx.countSolutions(empty, 2) == 2)

local clash = sudoku.copy(classic)
clash[3] = 5 -- a second 5 in the top row
check("clashing givens have no solution", dlx.countSolutions(clash, 2) == 0)
check("links restored after a clash", dlx.countSolutions(classic, 2) == 1)

local open = sudoku.copy(classic)
for i = 1, 81 do if i % 4 == 0 then open[i] = 0 end end
check("fewer clues, several solutions", dlx.countSolutions(open, 2) == sudoku.countSolutions(open, 2))

local function rng(n) return math.random(n) end
for _ = 1, 20 do
    check("random solution valid", sudoku.isValidSolution(dlx.randomSolution(rng)))
end

-- Both solvers agree on puzzles with clues removed at random
local agree = true
for _ = 1, 200 do
    local g = sudoku.copy(sudoku.randomSolution(rng))
    for i = 1, 81 do if math.random() < 0.6 then g[i] = 0 end end
    if dlx.countSolutions(g, 2) ~= sudoku.countSolutions(g, 2) then agree = false end
end
check("agrees with backtracking on 200 random puzzles", agree)

-- Generator with method "dlx": uniqueness checked by the other solver
local per = tonumber(arg and arg[1]) or 6
for _, diff in ipairs(sudoku.DIFFICULTIES) do
    local spec = sudoku.SPECS[diff]
    local t0 = os.clock()
    local exact = 0
    for _ = 1, per do
        local r = sudoku.generate(diff, rng, nil, "dlx")
        check(diff .. " unique", sudoku.countSolutions(r.puzzle, 2) == 1)
        local sym, consistent = true, true
        for i = 1, 81 do
            if (r.puzzle[i] == 0) ~= (r.puzzle[82 - i] == 0) then sym = false end
            if r.puzzle[i] ~= 0 and r.puzzle[i] ~= r.solution[i] then consistent = false end
        end
        check(diff .. " symmetric", sym)
        check(diff .. " givens match solution", consistent)
        check(diff .. " solution valid", sudoku.isValidSolution(r.solution))
        if r.grade >= spec.minGrade and r.grade <= spec.maxGrade then exact = exact + 1 end
    end
    print(string.format("dlx %-7s avg %5.1f ms  on-target %d/%d",
        diff, (os.clock() - t0) * 1000 / per, exact, per))
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
