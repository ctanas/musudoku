-- Run from the repository root:  luajit tests/test_history.lua
-- Recent solves: the list, labels and dates.
package.path = "./game/?.lua;" .. package.path
local history = require("src.history")

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

local function at(y, m, d, h, min) return os.time({ year = y, month = m, day = d, hour = h, min = min or 0 }) end

-- add keeps the newest first and at most MAX
local list = {}
for k = 1, history.MAX + 5 do history.add(list, { at = k, kind = "puzzle", time = k, hints = 0, mistakes = 0 }) end
check("capped", #list == history.MAX, #list)
check("newest first", list[1].time == history.MAX + 5 and list[#list].time == 6)

-- clean drops junk and keeps good entries
local cleaned = history.clean({
    { at = 1, kind = "daily", time = 90, difficulty = "hard", hints = 1 },
    { at = 2, kind = "bogus", time = 5 },
    "nope",
    { at = 3, kind = "pack", time = 60, pack = "Starter pack", index = 12, difficulty = "weird" },
})
check("clean keeps valid entries", #cleaned == 2, #cleaned)
check("clean fills missing counts", cleaned[1].mistakes == 0 and cleaned[1].hints == 1)
check("clean drops unknown difficulty", cleaned[2].difficulty == nil)
check("clean of nothing", #history.clean(nil) == 0)

-- labels and notes
check("puzzle label", history.label({ kind = "puzzle", difficulty = "master" }) == "Master")
check("daily label", history.label({ kind = "daily", difficulty = "easy" }) == "Daily, Easy")
check("pack label", history.label({ kind = "pack", pack = "Starter pack", index = 12 }) == "Starter pack #12")
check("perfect", history.note({ hints = 0, mistakes = 0 }) == "Perfect")
check("hints and mistakes", history.note({ hints = 2, mistakes = 1 }) == "1 mistake, 2 hints",
    history.note({ hints = 2, mistakes = 1 }))
check("one hint", history.note({ hints = 1, mistakes = 0 }) == "1 hint")

-- dates
local now = at(2026, 11, 1, 18)
check("today", history.when(at(2026, 11, 1, 14, 3), now) == "Today 14:03", history.when(at(2026, 11, 1, 14, 3), now))
check("yesterday", history.when(at(2026, 10, 31, 9, 12), now) == "Yesterday 09:12")
check("earlier", history.when(at(2026, 10, 28, 21, 40), now) == "28 Oct 21:40", history.when(at(2026, 10, 28, 21, 40), now))
check("yesterday across a month", history.when(at(2026, 11, 30, 8), at(2026, 12, 1, 10)) == "Yesterday 08:00")
check("unset clock", history.when(at(2000, 1, 1, 0), now) == "")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
