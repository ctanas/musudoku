-- Run from the repository root:  luajit tests/test_hints.lua [puzzles-per-difficulty]
-- Solves generated puzzles using only explained hints and checks every step.
package.path = "./game/?.lua;" .. package.path
local sudoku = require("src.sudoku")
local hints = require("src.hints")

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

math.randomseed(tonumber(os.getenv("SEED") or "") or 7)
local rng = function(n) return math.random(n) end
local per = tonumber(arg and arg[1]) or 15

local function nofixed() local f = {} for i = 1, 81 do f[i] = false end return f end

for _, diff in ipairs(sudoku.DIFFICULTIES) do
    local techniques, advanced, maxSteps, hintsUsed = {}, 0, 0, 0
    for _ = 1, per do
        local r = sudoku.generate(diff, rng)
        local values = sudoku.copy(r.puzzle)
        local fixed = {}
        for i = 1, 81 do fixed[i] = values[i] ~= 0 end
        for _ = 1, 81 do
            local done = true
            for i = 1, 81 do if values[i] == 0 then done = false break end end
            if done then break end

            local found = hints.search(values, r.solution, fixed)
            check("no false mistake", not found.mistake)
            if found.advanced then
                advanced = advanced + 1
                check("advanced reveals an empty cell", found.cell and values[found.cell] == 0)
                values[found.cell] = r.solution[found.cell]
            else
                local steps = found.steps
                if #steps > maxSteps then maxSteps = #steps end
                for k, s in ipairs(steps) do
                    techniques[s.technique] = (techniques[s.technique] or 0) + 1
                    if s.kind == "elim" then
                        check("elimination is not the last step", k < #steps)
                        for _, rem in ipairs(s.removals) do
                            check("never removes the right answer", r.solution[rem[1]] ~= rem[2],
                                s.technique .. " cell " .. rem[1])
                        end
                    else
                        check("placement is last", k == #steps)
                        check("placement is correct", r.solution[s.cell] == s.digit, s.technique)
                        check("placement on empty cell", values[s.cell] == 0)
                        values[s.cell] = s.digit
                    end
                end
                -- the presentation layer must accept every search result
                local shown = hints.build(values, r.solution, fixed)
                check("build returns steps or nothing when solved", type(shown) == "table")
            end
            hintsUsed = hintsUsed + 1
        end
        check(diff .. " solved by hints", table.concat(values) == table.concat(r.solution))
    end
    local parts = {}
    for t, n in pairs(techniques) do parts[#parts + 1] = t .. "=" .. n end
    table.sort(parts)
    print(string.format("%-7s advanced reveals %3d  longest hint %d steps  %s", diff, advanced, maxSteps, table.concat(parts, " ")))
end

-- Mistakes are reported first, preferring the selected cell
local r = sudoku.generate("easy", rng)
local values = sudoku.copy(r.solution)
local fixed = {}
for i = 1, 81 do fixed[i] = r.puzzle[i] ~= 0 end
local a, b
for i = 1, 81 do
    if not fixed[i] then
        if not a then a = i elseif not b then b = i end
    end
end
values[a] = values[a] % 9 + 1
values[b] = values[b] % 9 + 1
local found = hints.search(values, r.solution, fixed, b)
check("mistake found", found.mistake == b and found.mistakes == 2)
local shown = hints.build(values, r.solution, fixed, b)
check("mistake step erases", #shown == 1 and shown[1].action == "erase" and shown[1].target == b)

-- A hidden-single explanation names its blockers
values = sudoku.copy(r.puzzle)
shown = hints.build(values, r.solution, fixed)
local last = shown[#shown]
check("final step places a number", last.action == "place" and last.digit == r.solution[last.target])
check("final step has text", type(last.text) == "string" and #last.text > 20)

check("an 8", hints.article(8) == "an 8" and hints.article(7) == "a 7")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
