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

function PairPlay.new(app)
    local self = Board.init(setmetatable({}, PairPlay), app, "pairlink")
    self.links = {} -- [pair] = when its link effect started
    return self
end

-- Actions ---------------------------------------------------------------------

function PairPlay:beginLine()
    local g = self.game
    if not g:begin(g.cursor) then return self:blocked() end
    sound.play("note")
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

function PairPlay:eraseLine()
    local res = self.game:erase(self.game.cursor)
    if not res.changed then return end
    self.app.markPuzzleDirty("pairlink")
    sound.play("erase")
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

function PairPlay:update(dt)
    Board.update(self, dt)
    for k, start in pairs(self.links) do
        if self.t > start + self:linkLength(k) then self.links[k] = nil end
    end
end

function PairPlay:busy()
    return next(self.links) ~= nil or Board.busy(self)
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

    -- the numbers: their cell filled with the pair's colour, with an inner
    -- outline once linked
    local size = math.floor(cs * 0.5)
    local rings = {}
    for i = 1, self.n * self.n do
        local k = g.clues[i]
        if k ~= 0 then
            local cx, cy = self:center(i)
            local scale = self:flashScale(i)
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
