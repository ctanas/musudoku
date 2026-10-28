-- Run from the repository root:  luajit tests/test_packs.lua
package.path = "./game/?.lua;" .. package.path
local packs = require("src.packs")
local sudoku = require("src.sudoku")

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

local P = "53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79"
local Z = P:gsub("%.", "0")
local S = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"

-- parseLine
local kind, v = packs.parseLine(P)
check("dots line", kind == "one" and v == Z)
kind, v = packs.parseLine(Z)
check("zeros line", kind == "one" and v == Z)
kind, v = packs.parseLine("0000183b305c " .. Z .. "  1.2")
check("sudoku exchange format", kind == "one" and v == Z)
kind, v = packs.parseLine(P .. "," .. S .. ",30,0.0")
check("kaggle csv takes the puzzle, not the solution", kind == "one" and v == Z)
kind, v = packs.parseLine(P .. "\r")
check("crlf", kind == "one" and v == Z)
check("82-character run rejected", packs.parseLine(Z .. "1") == nil)
check("comment ignored", packs.parseLine("# " .. Z) == nil)
check("csv header ignored", packs.parseLine("puzzle,solution,clues,difficulty") == nil)
kind, v = packs.parseLine("5 3 . | . 7 . | . . .")
check("spaced grid row", kind == "row" and v == "530070000")
check("divider", packs.parseLine("------+-------+------") == "sep")

-- A file mixing every format
local path = os.tmpname()
local grid = {}
for r = 0, 8 do
    local row = Z:sub(r * 9 + 1, r * 9 + 9)
    grid[#grid + 1] = row:sub(1, 3) .. "|" .. row:sub(4, 6) .. "|" .. row:sub(7, 9)
    if r == 2 or r == 5 then grid[#grid + 1] = "---+---+---" end
end
local lines = {
    "# a comment",
    "puzzle,solution",
    P .. "," .. S,                       -- 1
    "",
    "Grid 01",
    table.concat(grid, "\n"),            -- 2 (9-line grid with dividers)
    "0000183b305c " .. Z .. "  1.2",     -- 3
    "Grid 02",
    "123",                               -- junk interrupts nothing
    Z,                                   -- 4
}
local f = io.open(path, "wb")
f:write((table.concat(lines, "\r\n") .. "\r\n"))
f:close()

local index = packs.scan(path)
check("found 4 puzzles", index and index.count == 4, index and index.count)
for n = 1, 4 do
    check("fetch " .. n, packs.fetch(index, n) == Z, packs.fetch(index, n))
end
check("fetch out of range", packs.fetch(index, 5) == nil)
local count = sudoku.solve(packs.toGrid(packs.fetch(index, 2)), 2)
check("fetched grid solves uniquely", count == 1)

-- Truncation
packs.MAX_PUZZLES = 2
local small = packs.scan(path)
check("truncated at max", small.count == 2 and small.truncated)
packs.MAX_PUZZLES = 100000
os.remove(path)

-- Missing file
local none = packs.scan("/nonexistent/file.txt")
check("missing file", none == nil)

-- Progress helpers
local progress = packs.loadProgress({ ["a.txt"] = { count = 5, size = 10, last = 2, solved = { 3 }, invalid = { 4 } } })
local p = progress["a.txt"]
check("next skips solved and invalid", packs.nextUnsolved(p, 5) == 5)
check("next wraps", packs.nextUnsolved(p, 5, 5) == 1)
p.solved[1], p.solved[2], p.solved[5] = true, true, true
check("all done", packs.nextUnsolved(p, 5) == nil)
check("random when all done", packs.randomUnsolved(p, 5) == nil)
local saved = packs.saveableProgress(progress)
check("saved as sorted lists", table.concat(saved["a.txt"].solved, ",") == "1,2,3,5")

-- Speed: 100,000-line file
local big = os.tmpname()
f = io.open(big, "wb")
for k = 1, 100000 do f:write(k, " ", P, "  rating 1.2\n") end
f:close()
local t0 = os.clock()
local bi = packs.scan(big)
local ms = (os.clock() - t0) * 1000
os.remove(big)
check("big file indexed", bi.count == 100000)
print(string.format("indexed 100,000 puzzles in %.0f ms", ms))

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
