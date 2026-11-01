-- Run from the repository root:  luajit tests/test_daily.lua
-- Daily puzzle dates, streaks and the repeatable random numbers.
package.path = "./game/?.lua;" .. package.path
local daily = require("src.daily")
local sudoku = require("src.sudoku")

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

local function at(y, m, d) return os.time({ year = y, month = m, day = d, hour = 12 }) end

-- today ---------------------------------------------------------------------------

local t = daily.today(at(2026, 11, 1))
check("key", t.key == "2026-11-01", t.key)
check("seed", t.seed == 20261101, t.seed)
check("label", t.label == "Sunday 1 November", t.label)
check("Sunday is expert", t.difficulty == "expert", t.difficulty)
check("Monday is easy", daily.today(at(2026, 11, 2)).difficulty == "easy")
check("Thursday is hard", daily.today(at(2026, 11, 5)).difficulty == "hard")
check("unset clock: no daily", daily.today(at(2000, 1, 1)) == nil)
check("1970 clock: no daily", daily.today(0) == nil)
check("label from key", daily.label("2026-12-25") == "Friday 25 December", daily.label("2026-12-25"))

-- previousKey ---------------------------------------------------------------------

check("previous day", daily.previousKey("2026-11-02") == "2026-11-01")
check("across a month", daily.previousKey("2026-03-01") == "2026-02-28", daily.previousKey("2026-03-01"))
check("leap day", daily.previousKey("2028-03-01") == "2028-02-29", daily.previousKey("2028-03-01"))
check("across a year", daily.previousKey("2027-01-01") == "2026-12-31")
check("not a key", daily.previousKey("yesterday") == nil)
check("isKey", daily.isKey("2026-11-01") and not daily.isKey("2026-11-1") and not daily.isKey(5))

-- streaks -------------------------------------------------------------------------

local days = {}
check("no days: no streak", daily.streak(days, "2026-11-01") == 0 and daily.bestStreak(days) == 0)
days["2026-10-30"], days["2026-10-31"] = 300, 250
check("today still open: streak runs to yesterday", daily.streak(days, "2026-11-01") == 2)
days["2026-11-01"] = 200
check("today solved", daily.streak(days, "2026-11-01") == 3)
check("a missed day ends it", daily.streak(days, "2026-11-03") == 0)
days["2026-10-01"], days["2026-10-02"] = 1, 1
check("best streak", daily.bestStreak(days) == 3, daily.bestStreak(days))
days["2026-10-29"] = 1 -- finished late: joins the run
check("late solve joins the streak", daily.streak(days, "2026-11-01") == 4 and daily.bestStreak(days) == 4)
check("solved count", daily.solvedCount(days) == 6, daily.solvedCount(days))
days["2026-12-30"], days["2026-12-31"], days["2027-01-01"] = 1, 1, 1
check("streak across new year", daily.streak(days, "2027-01-01") == 3)

-- rng -------------------------------------------------------------------------------

local function sequence(seed, n, range)
    local r, out = daily.rng(seed), {}
    for k = 1, n do out[k] = r(range) end
    return table.concat(out, ",")
end
check("same seed, same numbers", sequence(20261101, 200, 9) == sequence(20261101, 200, 9))
check("next day, different numbers", sequence(20261101, 50, 9) ~= sequence(20261102, 50, 9))
local r, lo, hi, seen = daily.rng(42), math.huge, -math.huge, {}
for _ = 1, 20000 do
    local v = r(9)
    lo, hi = math.min(lo, v), math.max(hi, v)
    seen[v] = (seen[v] or 0) + 1
end
check("range is 1..n", lo == 1 and hi == 9, lo .. ".." .. hi)
local even = true
for v = 1, 9 do
    if (seen[v] or 0) < 1800 or seen[v] > 2650 then even = false end
end
check("roughly even", even)

-- the same puzzle every time ------------------------------------------------------------

for _, key in ipairs({ "2026-11-01", "2026-11-02", "2026-11-05" }) do
    local d = daily.today(os.time({ year = tonumber(key:sub(1, 4)), month = tonumber(key:sub(6, 7)),
        day = tonumber(key:sub(9, 10)), hour = 12 }))
    local a = sudoku.generate(d.difficulty, daily.rng(d.seed), nil, "classic")
    local b = sudoku.generate(d.difficulty, daily.rng(d.seed), nil, "classic")
    check(key .. " builds the same puzzle twice", table.concat(a.puzzle) == table.concat(b.puzzle))
    check(key .. " has one solution", sudoku.countSolutions(a.puzzle, 2) == 1)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
