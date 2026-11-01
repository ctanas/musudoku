-- Run from the repository root:  luajit tests/test_records.lua
-- Per-difficulty records: counts, best times, perfect solves and streaks.
package.path = "./game/?.lua;" .. package.path
local records = require("src.records")

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

local e = records.empty()
check("empty", e.solved == 0 and e.best == 0 and e.streak == 0 and e.bestStreak == 0)
check("first solve is a best", records.solve(e, 300, 0, 0) == true and e.best == 300)
check("perfect counted", e.perfect == 1)
check("slower isn't a best", records.solve(e, 400, 0, 2) == false and e.best == 300)
check("mistakes aren't perfect", e.perfect == 1)
check("hints never set a best", records.solve(e, 100, 1, 0) == false and e.best == 300)
check("totals", e.solved == 3 and e.total == 800)
check("streak grows", e.streak == 3 and e.bestStreak == 3)
records.abandon(e)
check("abandoning ends the streak", e.streak == 0 and e.bestStreak == 3)
records.solve(e, 500, 0, 0)
check("a new streak starts", e.streak == 1 and e.bestStreak == 3)
for _ = 1, 3 do records.solve(e, 500, 0, 0) end
check("best streak follows a longer one", e.streak == 4 and e.bestStreak == 4)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
