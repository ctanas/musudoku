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
    -- Below Master, every puzzle can be solved with the techniques hints explain.
    if diff ~= "master" then check(diff .. ": no advanced reveals", advanced == 0, advanced) end
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

-- Pattern finders on hand-made candidates (every digit open everywhere,
-- except where a pattern is cut out).
local DB = sudoku.DIGIT_BIT
local function openBoard()
    local v, c = {}, {}
    for i = 1, 81 do v[i], c[i] = 0, 511 end
    return v, c
end
local function cell(r, c) return r * 9 + c + 1 end
local function removalSet(e)
    local s = {}
    for _, r in ipairs(e.removals) do s[r[1] .. ":" .. r[2]] = true end
    return s
end

-- X-Wing: in rows 1 and 5, 5 only fits in columns 2 and 7.
local v, c = openBoard()
for _, r in ipairs({ 0, 4 }) do
    for col = 0, 8 do
        if col ~= 1 and col ~= 6 then c[cell(r, col)] = c[cell(r, col)] - DB[5] end
    end
end
local e = hints._fishes(c)
check("X-Wing found", e and e.technique == "xWing" and e.digit == 5, e and e.technique)
if e then
    local s = removalSet(e)
    check("X-Wing removes 5 from both columns elsewhere", #e.removals == 14
        and s[cell(2, 1) .. ":5"] and s[cell(8, 6) .. ":5"] and not s[cell(0, 1) .. ":5"], #e.removals)
end

-- Swordfish in columns: 3 only fits in rows 1, 4 and 8 of columns 1, 5 and 9,
-- and not in all three of them in any column.
v, c = openBoard()
local fishCols, fishRows = { 0, 4, 8 }, { 0, 3, 7 }
local keep = { [0] = { 0, 3 }, [4] = { 3, 7 }, [8] = { 0, 7 } }
for _, col in ipairs(fishCols) do
    local allowed = {}
    for _, r in ipairs(keep[col]) do allowed[r] = true end
    for r = 0, 8 do
        if not allowed[r] then c[cell(r, col)] = c[cell(r, col)] - DB[3] end
    end
end
e = hints._fishes(c)
check("Swordfish found", e and e.technique == "swordfish" and e.digit == 3, e and e.technique)
if e then
    local s = removalSet(e)
    local ok = true
    for _, r in ipairs(fishRows) do
        for col = 0, 8 do
            local inFish = col == 0 or col == 4 or col == 8
            if inFish == (s[cell(r, col) .. ":3"] or false) then ok = false end
        end
    end
    check("Swordfish clears its rows outside the three columns", ok and #e.removals == 18, #e.removals)
end

-- XY-Wing: pivot r1c1 is 1 or 2, wings r1c5 (1 or 3) and r5c1 (2 or 3).
-- Only r5c5 sees both wings, so it loses the 3.
v, c = openBoard()
local p, qa, qb = cell(0, 0), cell(0, 4), cell(4, 0)
c[p], c[qa], c[qb] = DB[1] + DB[2], DB[1] + DB[3], DB[2] + DB[3]
e = hints._xyWing(v, c)
check("XY-Wing found", e and e.technique == "xyWing" and e.pivot == p and e.digit == 3, e and e.technique)
if e then
    check("XY-Wing removes 3 where both wings are seen", #e.removals == 1
        and e.removals[1][1] == cell(4, 4) and e.removals[1][2] == 3)
    check("XY-Wing wings follow the pivot's digits", e.wings[1] == qa and e.digits[1] == 1 and e.digits[2] == 2)
end

-- An XY-Wing whose wings share the pivot's digit isn't one.
v, c = openBoard()
c[p], c[qa], c[qb] = DB[1] + DB[2], DB[1] + DB[3], DB[1] + DB[3]
check("no XY-Wing with matching wings", hints._xyWing(v, c) == nil)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
