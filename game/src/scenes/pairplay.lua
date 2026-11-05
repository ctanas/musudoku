local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local input = require("src.input")
local Board = require("src.boardscene")

-- The Pairlink play screen. boardscene.lua does the layout, cursor, pausing
-- and celebrating; this adds drawing lines and the side panel.
--
-- A on a number (or a line) starts drawing, and the D-pad then draws the
-- line cell by cell; stepping back along it takes steps back. Reaching the
-- pair's other number links them and stops drawing, and so do A and B.
-- Breaking a linked line (B, or A on it to draw it again) snaps it.
local PairPlay = Board.extend({})

local RULES = {
    "Join each pair of matching numbers with a line.",
    "Lines go up, down, left or right, and never cross or branch.",
    "Every cell is used.",
}

local DIRS = { up = { -1, 0 }, down = { 1, 0 }, left = { 0, -1 }, right = { 0, 1 } }

-- The link effect: a bead runs along the line (this long per cell), then
-- the far number pops; each number's ring lasts RING.
local STEP, POP, RING = 0.035, 0.25, 0.45

-- The snap, when a linked line is broken: sparks fly from the break for
-- SPARK_TIME, and each loose piece recoils into its number in RECOIL plus
-- RECOIL_CELL per cell, the number flinching for LAND when it arrives.
local SPARKS, SPARK_TIME = 7, 0.34
local RECOIL, RECOIL_CELL, LAND = 0.22, 0.012, 0.2

function PairPlay.new(app)
    local self = Board.init(setmetatable({}, PairPlay), app, "pairlink")
    self.links = {} -- [pair] = when its link effect started
    self.snaps = {} -- lines breaking: { pair, t, at = cell, pieces, sparks }
    return self
end

local function copy(list)
    local out = {}
    for n, x in ipairs(list) do out[n] = x end
    return out
end

local function indexOf(list, x)
    for n, y in ipairs(list) do
        if y == x then return n end
    end
end

-- line[from] to line[to], in that order.
local function span(line, from, to)
    local cells = {}
    for s = from, to, (to >= from) and 1 or -1 do cells[#cells + 1] = line[s] end
    return cells
end

-- Actions ---------------------------------------------------------------------

-- Pair k's line was linked and broke at cell `at`. pieces are the parts
-- that went, each listed from the number it recoils into to the break.
function PairPlay:snap(k, at, pieces)
    self.links[k] = nil -- its link effect, if it's still running
    local snap = { pair = k, t = self.t, at = at, pieces = {}, sparks = {} }
    for _, cells in ipairs(pieces) do
        for _, i in ipairs(cells) do self.flash[i] = nil end
        if #cells >= 2 then
            snap.pieces[#snap.pieces + 1] = { cells = cells, length = RECOIL + RECOIL_CELL * #cells }
        end
    end
    for s = 1, SPARKS do
        snap.sparks[s] = {
            angle = (s + 0.8 * love.math.random()) * 2 * math.pi / SPARKS,
            reach = 0.55 + 0.45 * love.math.random(),
        }
    end
    self.snaps[#self.snaps + 1] = snap
    sound.play("snap")
end

-- A on a number or a line. On a linked line that breaks it: the line is cut
-- there to draw on, and the rest recoils into the number at its far end
-- (on a number, the whole line recoils into the other one).
function PairPlay:beginLine()
    local g = self.game
    local i = g.cursor
    local k = g:pairAt(i)
    local before = (k ~= 0 and g:isLinked(k)) and copy(g.lines[k]) or nil
    if not g:begin(i) then return self:blocked() end
    if not before then return sound.play("note") end
    if before[#before] == i then before = span(before, #before, 1) end
    self:snap(k, i, { span(before, #before, indexOf(before, i)) })
end

-- One step of the line being drawn.
function PairPlay:extend(dr, dc)
    local g = self.game
    local j = self:neighbour(g:head(), dr, dc)
    if not j then return self:blocked() end
    local k = g.active
    local res = g:step(j)
    if res.blocked then return self:blocked() end
    g.cursor = g:head()
    self.app.markPuzzleDirty("pairlink")
    if res.linked then
        local done = g:finish()
        self:linked(k)
        if done.solved then self:startWin(g.cursor) end
    else
        sound.play("move")
    end
end

function PairPlay:endLine()
    local g = self.game
    if not g.active then return end
    local res = g:finish()
    sound.play("note")
    if res.changed then self.app.markPuzzleDirty("pairlink") end
    if res.solved then self:startWin(g.cursor) end
end

-- B: a linked line breaks where the cursor is, each side recoiling into its
-- number.
function PairPlay:eraseLine()
    local g = self.game
    local i = g.cursor
    local k = g:pairAt(i)
    local before = (k ~= 0 and g:isLinked(k)) and copy(g.lines[k]) or nil
    local res = g:erase(i)
    if not res.changed then return end
    self.app.markPuzzleDirty("pairlink")
    if not before then return sound.play("erase") end
    local s = indexOf(before, i) or 1
    self:snap(k, before[s], { span(before, 1, s), span(before, #before, s) })
end

-- L1 / R1: to the previous / next pair that isn't linked yet: the end of its
-- line, or its first number.
function PairPlay:jumpPair(dir)
    local g = self.game
    local current = g:pairAt(g.cursor)
    if current == 0 then current = (dir > 0) and 0 or g.pairs + 1 end
    for s = 1, g.pairs do
        local k = (current - 1 + dir * s) % g.pairs + 1
        if not g:isLinked(k) then
            local line = g.lines[k]
            g.cursor = line[#line] or g.ends[k][1]
            sound.play("move")
            return
        end
    end
    self:blocked()
end

-- A pair's line reached its other number: a bright bead runs along the
-- line while its cells flash in turn, and both numbers pop with a square
-- ring.
function PairPlay:linked(k)
    local line = self.game.lines[k]
    self.links[k] = self.t
    for s, i in ipairs(line) do
        local start = self.t + (s - 1) * STEP
        if not self.flash[i] or self.flash[i] < start then self.flash[i] = start end
    end
    sound.play("link")
end

function PairPlay:pause()
    self:endLine()
    Board.pause(self)
end

function PairPlay:action(a)
    if self.winT then return end
    local g = self.game
    if a == "start" or a == "menu" then return self:pause() end
    local dir = DIRS[a]
    if g.active then
        if dir then self:extend(dir[1], dir[2])
        elseif a == "a" or a == "b" then self:endLine()
        elseif a == "l2" or a == "r2" then
            self:endLine()
            self:history(a == "l2" and "undo" or "redo")
        end
        return
    end
    if dir then self:move(dir[1], dir[2])
    elseif a == "a" then self:beginLine()
    elseif a == "b" or a == "erase" then self:eraseLine()
    elseif a == "l1" or a == "r1" then self:jumpPair(a == "l1" and -1 or 1)
    elseif a == "l2" then self:history("undo")
    elseif a == "r2" then self:history("redo")
    end
end

-- Update ----------------------------------------------------------------------

-- How long pair k's link effect runs, from the bead's start to the far
-- number's ring fading.
function PairPlay:linkLength(k)
    return (#self.game.lines[k] - 1) * STEP + RING
end

-- How long a snap runs, to its last spark or flinch.
local function snapLength(snap)
    local length = SPARK_TIME
    for _, piece in ipairs(snap.pieces) do length = math.max(length, piece.length + LAND) end
    return length
end

function PairPlay:update(dt)
    Board.update(self, dt)
    for k, start in pairs(self.links) do
        if self.t > start + self:linkLength(k) then self.links[k] = nil end
    end
    for n = #self.snaps, 1, -1 do
        local snap = self.snaps[n]
        if self.t > snap.t + snapLength(snap) then table.remove(self.snaps, n) end
    end
end

function PairPlay:busy()
    return next(self.links) ~= nil or #self.snaps > 0 or Board.busy(self)
end

-- Drawing ---------------------------------------------------------------------

-- Flashing cells take their line's colour.
function PairPlay:flashColor(i, alpha)
    local k = self.game.owner[i]
    if k ~= 0 then theme.setLine(k, alpha) else theme.set("accent", alpha) end
end

function PairPlay:center(i)
    local x, y = self:cellPos(i)
    return x + self.cs / 2, y + self.cs / 2
end

-- When number i of pair k pops during its link effect, or nil.
function PairPlay:popTime(k, i)
    local start = self.links[k]
    if not start then return nil end
    local line = self.game.lines[k]
    if i == line[1] then return start end
    return start + (#line - 1) * STEP
end

-- The bead running along pair k's line, with a soft glow (drawn additively,
-- so it brightens whatever colour it passes over).
function PairPlay:drawBead(k, width)
    local line = self.game.lines[k]
    local pos = (self.t - self.links[k]) / STEP
    if pos < 0 or pos > #line - 1 then return end
    local s = math.floor(pos)
    local f = pos - s
    local x1, y1 = self:center(line[s + 1])
    local x2, y2 = self:center(line[math.min(#line, s + 2)])
    local x, y = x1 + (x2 - x1) * f, y1 + (y2 - y1) * f
    love.graphics.setBlendMode("add")
    theme.setLine(k, 0.55)
    love.graphics.circle("fill", x, y, width * 2)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.circle("fill", x, y, width * 0.8)
    love.graphics.setBlendMode("alpha")
end

-- The loose pieces of breaking lines, each shrinking back along its cells
-- into its number, fast and then slowing, a little thinner as it goes.
function PairPlay:drawSnapPieces(width)
    for _, snap in ipairs(self.snaps) do
        for _, piece in ipairs(snap.pieces) do
            local p = (self.t - snap.t) / piece.length
            if p < 1 then
                local e = 1 - (1 - p) ^ 3
                local cells = piece.cells
                local rest = (#cells - 1) * (1 - e)
                local whole = math.floor(rest)
                local points = {}
                for s = 1, whole + 1 do
                    local x, y = self:center(cells[s])
                    points[#points + 1], points[#points + 2] = x, y
                end
                local f = rest - whole
                if f > 0 then
                    local x1, y1 = self:center(cells[whole + 1])
                    local x2, y2 = self:center(cells[whole + 2])
                    points[#points + 1], points[#points + 2] = x1 + (x2 - x1) * f, y1 + (y2 - y1) * f
                end
                local w = width * (1 - 0.3 * e)
                theme.setLine(snap.pair, 1 - 0.25 * e)
                love.graphics.setLineWidth(w)
                if #points >= 4 then love.graphics.line(points) end
                for q = 1, #points, 2 do love.graphics.circle("fill", points[q], points[q + 1], w / 2) end
            end
        end
    end
end

-- Sparks flying out of each break, short streaks in the line's colour, with
-- a bright core flashing where it broke and a ring spreading from it.
function PairPlay:drawSnapSparks(width)
    local cs = self.cs
    for _, snap in ipairs(self.snaps) do
        local q = (self.t - snap.t) / SPARK_TIME
        if q < 1 then
            local cx, cy = self:center(snap.at)
            local e = ui.ease(q)
            if q < 0.35 then
                local f = 1 - q / 0.35
                theme.setLine(snap.pair, f)
                love.graphics.circle("fill", cx, cy, width * 1.1 * f)
                love.graphics.setBlendMode("add")
                love.graphics.setColor(1, 1, 1, 0.8 * f)
                love.graphics.circle("fill", cx, cy, width * 0.7 * f)
                love.graphics.setBlendMode("alpha")
            end
            theme.setLine(snap.pair, 0.7 * (1 - q) ^ 2)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line", cx, cy, cs * (0.15 + 0.6 * e))
            theme.setLine(snap.pair, 1 - q)
            love.graphics.setLineWidth(math.max(3, width * 0.55))
            for _, spark in ipairs(snap.sparks) do
                local dx, dy = math.cos(spark.angle), math.sin(spark.angle)
                local outer = cs * (0.25 + 0.95 * spark.reach * e)
                local inner = outer - cs * 0.32 * (1 - q)
                love.graphics.line(cx + dx * inner, cy + dy * inner, cx + dx * outer, cy + dy * outer)
            end
        end
    end
end

-- How much number i shrinks as a loose piece lands in it (1 for not at all).
function PairPlay:landScale(i)
    local scale = 1
    for _, snap in ipairs(self.snaps) do
        for _, piece in ipairs(snap.pieces) do
            if piece.cells[1] == i then
                local p = (self.t - snap.t - piece.length) / LAND
                if p >= 0 and p < 1 then scale = scale * (1 - 0.13 * math.sin(math.pi * p)) end
            end
        end
    end
    return scale
end

function PairPlay:drawBoard()
    local g, cs = self.game, self.cs

    -- cells a line uses are tinted with its colour
    self:drawSurface(function(x, y, i)
        local k = g.owner[i]
        if k ~= 0 then
            theme.setLine(k, 0.16)
            ui.rect("fill", x, y, cs, cs)
        end
    end)
    if self.hidden then return end

    -- the lines, with rounded corners and ends
    local width = math.max(4, math.floor(cs * 0.14))
    love.graphics.setLineWidth(width)
    for k, line in ipairs(g.lines) do
        if #line >= 2 then
            theme.setLine(k, (g.active == k or g:isLinked(k)) and 1 or 0.85)
            local points = {}
            for _, i in ipairs(line) do
                local cx, cy = self:center(i)
                points[#points + 1] = cx
                points[#points + 1] = cy
            end
            love.graphics.line(points)
            for p = 1, #points, 2 do love.graphics.circle("fill", points[p], points[p + 1], width / 2) end
        end
    end
    for k in pairs(self.links) do self:drawBead(k, width) end
    self:drawSnapPieces(width)

    -- the numbers: their cell filled with the pair's colour, with an inner
    -- outline once linked
    local size = math.floor(cs * 0.5)
    local rings = {}
    for i = 1, self.n * self.n do
        local k = g.clues[i]
        if k ~= 0 then
            local cx, cy = self:center(i)
            local scale = self:flashScale(i) * self:landScale(i)
            local at = self:popTime(k, i)
            if at and self.t >= at then
                local p = (self.t - at) / POP
                if p < 1 then scale = scale * (1 + 0.14 * math.sin(math.pi * p)) end
                local q = (self.t - at) / RING
                if q < 1 then rings[#rings + 1] = { k, cx, cy, q } end
            end
            local half = (cs / 2 - 1) * scale
            theme.setLine(k)
            ui.rect("fill", cx - half, cy - half, half * 2, half * 2, 3)
            if g:isLinked(k) then
                theme.set("board", 0.6)
                love.graphics.setLineWidth(2)
                local inset = half - 5
                ui.rect("line", cx - inset, cy - inset, inset * 2, inset * 2, 3)
            end
            theme.set("board")
            Board.drawText(tostring(k), cx, cy, size, "bold", scale)
        end
    end
    -- a square ring growing out of each number that just linked, over its
    -- neighbours
    love.graphics.setLineWidth(3)
    for _, ring in ipairs(rings) do
        local k, cx, cy, q = ring[1], ring[2], ring[3], ring[4]
        local half = cs / 2 + 2 + 14 * ui.ease(q)
        theme.setLine(k, 0.8 * (1 - q) ^ 2)
        ui.rect("line", cx - half, cy - half, half * 2, half * 2, 6)
    end

    self:drawRings()
    -- with a halo in the board's colour, so it shows on a square of its
    -- own colour
    if g.active then
        self:drawCursor(function() theme.setLine(g.active) end, 4, true)
    else
        self:drawCursor(nil, 3, true)
    end
    -- over the cursor, which is usually where the line broke
    self:drawSnapSparks(width)
end

function PairPlay:drawPanel()
    local g, x = self.game, Board.PX
    self:drawHeader(x, 46)
    local total = g.size * g.size
    self:drawProgress(x, 58, g:filledCount() / total)
    Board.drawCounter("Linked", g:linkedCount() .. " of " .. g.pairs, x, 82)
    Board.drawRules(x, 104, "Pairlink", RULES)

    local undo = { { input.label("l2"), "Undo" }, { input.label("r2"), "Redo" } }
    if g.active then
        local top = Board.drawLegend({ { { "A", "Stop drawing" } }, undo })
        theme.set("muted")
        ui.text("Move to draw. Step back along the line to take steps back.",
            x, top - 74, 15, "regular", "left", Board.PW)
    else
        local top = Board.drawLegend({ { { "A", "Draw" }, { "B", "Erase" } }, undo })
        -- its own row, so its wide glyph doesn't push the columns apart
        ui.hints({ { input.pair("l1"), "Next pair" } }, x, top - 32, "left", nil, 20, 1.2)
    end
end

function PairPlay:draw()
    self:drawBoard()
    self:drawPanel()
    self:drawConfetti()
end

return PairPlay
