-- Run from the repository root:  luajit tests/test_sudoku.lua [puzzles-per-difficulty]
package.path = "./game/?.lua;" .. package.path

local sudoku = require("src.sudoku")

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

-- Structure tables
check("27 units", #sudoku.UNITS == 27)
local peersOk = true
for i = 1, 81 do if #sudoku.PEERS[i] ~= 20 then peersOk = false end end
check("20 peers per cell", peersOk)

-- Known puzzle with a unique solution
local classic = parse([[
53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79]])
local count, solution = sudoku.solve(classic, 2)
check("classic puzzle unique", count == 1, "count " .. tostring(count))
check("classic solution valid", solution and sudoku.isValidSolution(solution))
check("classic solution starts 534678912",
    solution and table.concat(solution, "", 1, 9) == "534678912")
check("classic grades as singles", sudoku.grade(classic) <= 2, "grade " .. sudoku.grade(classic))

-- Ambiguous puzzle (two 3s and two 4s can swap)
local multi = sudoku.copy(solution)
multi[1] = 0
multi[2] = 0
multi[10] = 0
multi[11] = 0
check("count stops at limit", sudoku.countSolutions(multi, 2) <= 2)

-- Clashing givens
local bad = parse([[
55..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79]])
check("clashing givens have no solution", sudoku.countSolutions(bad, 2) == 0)

-- A known puzzle that needs more than singles (Arto Inkala's "hardest")
local inkala = parse([[
8..........36......7..9.2...5...7.......457.....1...3...1....68..85...1..9....4..]])
check("Inkala unique", sudoku.countSolutions(inkala, 2) == 1)
check("Inkala grades advanced", sudoku.grade(inkala) == 5, "grade " .. sudoku.grade(inkala))

-- Random solutions
math.randomseed(tonumber(os.getenv("SEED") or "") or os.time())
local function rng(n) return math.random(n) end
for _ = 1, 20 do
    check("random solution valid", sudoku.isValidSolution(sudoku.randomSolution(rng)))
end

-- Generator: uniqueness, symmetry, clue counts and grades per difficulty
local per = tonumber(arg and arg[1]) or 6
for _, diff in ipairs(sudoku.DIFFICULTIES) do
    local spec = sudoku.SPECS[diff]
    local t0 = os.clock()
    local grades, clueTotal, exact = {}, 0, 0
    for _ = 1, per do
        local r = sudoku.generate(diff, rng)
        check(diff .. " unique", sudoku.countSolutions(r.puzzle, 2) == 1)
        local sym, consistent = true, true
        for i = 1, 81 do
            if (r.puzzle[i] == 0) ~= (r.puzzle[82 - i] == 0) then sym = false end
            if r.puzzle[i] ~= 0 and r.puzzle[i] ~= r.solution[i] then consistent = false end
        end
        check(diff .. " symmetric", sym)
        check(diff .. " givens match solution", consistent)
        check(diff .. " solution valid", sudoku.isValidSolution(r.solution))
        grades[#grades + 1] = r.grade
        clueTotal = clueTotal + r.clues
        if r.grade >= spec.minGrade and r.grade <= spec.maxGrade then exact = exact + 1 end
    end
    local ms = (os.clock() - t0) * 1000 / per
    print(string.format("%-7s avg %5.1f ms  avg clues %4.1f  on-target %d/%d  grades %s",
        diff, ms, clueTotal / per, exact, per, table.concat(grades, ",")))
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
