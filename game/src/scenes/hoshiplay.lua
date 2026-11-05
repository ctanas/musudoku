local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local input = require("src.input")
local Board = require("src.boardscene")

-- The Hoshi play screen. boardscene.lua does the layout, cursor, pausing and
-- celebrating; this adds islands, bridges and the side panel.
--
-- The cursor goes from island to island. A starts drawing at the island it's
-- on, as in Pairlink: each direction then draws a bridge to the island that
-- way and the cursor goes on to it, so one bridge can follow another.
-- Drawing over a bridge makes it two, and over two takes them away (next to
-- a 1, over one takes it away). A or B stops drawing.
local HoshiPlay = Board.extend({})

local RULES = {
    "Join the islands with straight bridges, at most two between any two.",
    "Each number is how many bridges its island has.",
    "Bridges never cross, and every island connects.",
}

local DIRS = { up = true, down = true, left = true, right = true }

local GROW = 0.14    -- a new bridge reaching across
local POP = 0.2      -- an island bumping when its bridges change
local IN_WAY = 0.5   -- the bridge in the way glowing red

function HoshiPlay.new(app)
    local self = Board.init(setmetatable({}, HoshiPlay), app, "hoshi")
    self.slideFar = true -- the cursor glides between islands, however far apart
    self.pops = {}       -- [island] = when it bumped
    self.grows = {}      -- [link] = { t, from = island, count }
    return self
end

-- Sizes that follow the cell size: the islands' radius, and the bridges'
-- width and the gap between a double bridge's two lines.
function HoshiPlay:radius()
    return self.cs * 0.38
end

function HoshiPlay:center(i)
    local x, y = self:cellPos(i)
    return x + self.cs / 2, y + self.cs / 2
end

-- Actions ---------------------------------------------------------------------

function HoshiPlay:moveToward(dir)
    local g = self.game
    local j = g:nextIsland(g.cursor, dir)
    if not j then return self:blocked() end
    g.cursor = j
    sound.play("move")
end

function HoshiPlay:beginDrawing()
    self.drawing = true
    sound.play("note")
end

function HoshiPlay:endDrawing(silent)
    if not self.drawing then return end
    self.drawing = false
    if not silent then sound.play("note") end
end

function HoshiPlay:bump(l)
    local link = self.game.P.links[l]
    self.pops[link.a], self.pops[link.b] = self.t, self.t
end

-- One bridge drawn from the cursor's island toward dir, the cursor going on
-- to the island at its other end.
function HoshiPlay:extend(dir)
    local g = self.game
    local from = g.cursor
    local res = g:cycle(from, dir)
    if res.blocked then
        if res.link then self.inWay = { link = res.link, t = self.t } end
        return self:blocked()
    end
    local link = g.P.links[res.link]
    g.cursor = (link.a == from) and link.b or link.a
    self.app.markPuzzleDirty("hoshi")
    self:bump(res.link)
    if res.added then
        self.grows[res.link] = { t = self.t, from = from, count = res.count }
        local done = g:state(link.a) == "done" or g:state(link.b) == "done"
        sound.play(done and "link" or "place")
    else
        self.grows[res.link] = nil
        sound.play("erase")
    end
    if res.solved then
        self:endDrawing(true)
        self:startWin(g.cursor)
    end
end

function HoshiPlay:clearIsland()
    local g = self.game
    local res = g:clearIsland(g.cursor)
    if not res.changed then return end
    self.app.markPuzzleDirty("hoshi")
    for _, l in ipairs(res.links) do
        self:bump(l)
        self.grows[l] = nil
    end
    sound.play("erase")
end

-- L1 / R1: to the next / previous island that's still short of its number
-- or over it.
function HoshiPlay:jumpUnfinished(dir)
    local g = self.game
    local j = g:nextUnfinished(g.cursor, dir)
    if not j then return self:blocked() end
    g.cursor = j
    sound.play("move")
end

function HoshiPlay:history(which)
    self.grows = {}
    Board.history(self, which)
end

function HoshiPlay:pause()
    self:endDrawing(true)
    Board.pause(self)
end

function HoshiPlay:action(a)
    if self.winT then return end
    if a == "start" or a == "menu" then return self:pause() end
    if self.drawing then
        if DIRS[a] then self:extend(a)
        elseif a == "a" or a == "b" then self:endDrawing()
        elseif a == "l2" or a == "r2" then
            self:endDrawing(true)
            self:history(a == "l2" and "undo" or "redo")
        end
        return
    end
    if DIRS[a] then self:moveToward(a)
    elseif a == "a" then self:beginDrawing()
    elseif a == "b" or a == "erase" then self:clearIsland()
    elseif a == "l1" or a == "r1" then self:jumpUnfinished(a == "l1" and -1 or 1)
    elseif a == "l2" then self:history("undo")
    elseif a == "r2" then self:history("redo")
    end
end

-- Update ----------------------------------------------------------------------

function HoshiPlay:update(dt)
    Board.update(self, dt)
    for i, t in pairs(self.pops) do
        if self.t > t + POP then self.pops[i] = nil end
    end
    for l, grow in pairs(self.grows) do
        if self.t > grow.t + GROW then self.grows[l] = nil end
    end
    if self.inWay and self.t > self.inWay.t + IN_WAY then self.inWay = nil end
end

function HoshiPlay:busy()
    if next(self.pops) ~= nil or next(self.grows) ~= nil or self.inWay then return true end
    return Board.busy(self)
end

-- Drawing ---------------------------------------------------------------------

-- One straight line from (x1, y1) to (x2, y2), drawn only up to fraction p.
local function partLine(x1, y1, x2, y2, p)
    love.graphics.line(x1, y1, x1 + (x2 - x1) * p, y1 + (y2 - y1) * p)
end

function HoshiPlay:drawBridges()
    local g, cs = self.game, self.cs
    local width = math.max(3, math.floor(cs * 0.08 + 0.5))
    local gap = math.max(5, math.floor(cs * 0.13 + 0.5))
    love.graphics.setLineWidth(width)
    for l, link in ipairs(g.P.links) do
        local count = g.counts[l]
        if count > 0 then
            -- from the island it was built from, so a new one can reach across
            local grow = self.grows[l]
            local from, to = link.a, link.b
            if grow and grow.from == link.b then from, to = link.b, link.a end
            local x1, y1 = self:center(from)
            local x2, y2 = self:center(to)
            local p = grow and ui.ease(math.min(1, (self.t - grow.t) / GROW)) or 1
            local inWay = self.inWay and self.inWay.link == l
            if inWay then
                theme.mix("user", "error", 1 - (self.t - self.inWay.t) / IN_WAY)
            else
                theme.set("user")
            end
            if count == 1 then
                partLine(x1, y1, x2, y2, p)
            else
                -- two lines side by side; when the second was just added,
                -- only it grows
                local ox, oy = 0, 0
                if link.horizontal then oy = gap / 2 else ox = gap / 2 end
                local firstP = (grow and grow.count == 2) and 1 or p
                partLine(x1 - ox, y1 - oy, x2 - ox, y2 - oy, firstP)
                partLine(x1 + ox, y1 + oy, x2 + ox, y2 + oy, p)
            end
        end
    end
end

-- While drawing: a faint line to each island a bridge could still go to.
function HoshiPlay:drawGuides()
    local g = self.game
    if not self.drawing then return end
    love.graphics.setLineWidth(2)
    theme.set("mark", 0.45)
    for _, dir in ipairs({ "up", "down", "left", "right" }) do
        local l = g:linkToward(g.cursor, dir)
        if l and g.counts[l] == 0 and not g:crossing(l) then
            local link = g.P.links[l]
            local x1, y1 = self:center(link.a)
            local x2, y2 = self:center(link.b)
            love.graphics.line(x1, y1, x2, y2)
        end
    end
end

function HoshiPlay:drawIslands()
    local g = self.game
    local r0 = self:radius()
    local size = math.floor(self.cs * 0.46)
    for _, i in ipairs(g.P.islands) do
        local cx, cy = self:center(i)
        local scale = self:flashScale(i)
        local pop = self.pops[i]
        if pop then
            local p = (self.t - pop) / POP
            if p < 1 then scale = scale * (1 + 0.12 * math.sin(math.pi * p)) end
        end
        local r = r0 * scale
        -- the winning wave: a glow behind each island as it passes
        local f = self.flash[i]
        if f and self.t >= f then
            local p = (self.t - f) / Board.FLASH_TIME
            if p <= 1 then
                theme.set("accent", math.sin(math.pi * p) * 0.6)
                love.graphics.circle("fill", cx, cy, r + 7)
            end
        end
        local state = g:state(i)
        theme.set("board")
        love.graphics.circle("fill", cx, cy, r)
        if state == "done" then
            theme.set("user", 0.22)
            love.graphics.circle("fill", cx, cy, r)
        end
        love.graphics.setLineWidth(2.5)
        theme.set(state == "over" and "error" or (state == "done" and "user" or "given"))
        love.graphics.circle("line", cx, cy, r)
        theme.set(state == "over" and "error" or "given", state == "done" and 0.85 or 1)
        Board.drawText(tostring(g.clues[i]), cx, cy, size, "bold", scale)
    end
end

-- The cursor: a ring around its island, sliding between islands, with a
-- halo in the board's colour so it shows over bridges.
function HoshiPlay:drawCursor()
    if self.winT then return end
    local dx = 0
    if self.shake > 0 then dx = math.sin(self.shake * 70) * 4 * (self.shake / 0.25) end
    local cx, cy = self.vx + self.cs / 2 + dx, self.vy + self.cs / 2
    local r = self:radius() + 6
    local width = self.drawing and 4 or 3
    theme.set("board")
    love.graphics.setLineWidth(width + 4)
    love.graphics.circle("line", cx, cy, r)
    theme.set(self.drawing and "accent" or "mark")
    love.graphics.setLineWidth(width)
    love.graphics.circle("line", cx, cy, r)
end

function HoshiPlay:drawBoard()
    local g, cs, n = self.game, self.cs, self.n
    local bx, by, bs = self.bx, self.by, self.bs
    theme.frame(bx, by, bs, bs)
    theme.set("board")
    ui.rect("fill", bx, by, bs, bs, 8)

    -- the cursor's row and column, so the islands in line with it stand out
    love.graphics.stencil(function() ui.rect("fill", bx, by, bs, bs, 8) end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    if not self.hidden and not self.winT then
        local x, y = self:cellPos(g.cursor)
        theme.set("peer")
        ui.rect("fill", bx, y, bs, cs)
        ui.rect("fill", x, by, cs, bs)
    end
    theme.texture(bx, by, bs, bs)
    love.graphics.setStencilTest()
    theme.set("boxLine")
    love.graphics.setLineWidth(3)
    ui.rect("line", bx, by, bs, bs, 8)
    if self.hidden then return end

    -- water: a faint dot in every cell without an island
    theme.set("line")
    local dot = math.max(1.5, cs * 0.04)
    for i = 1, n * n do
        if g.clues[i] == 0 then
            local x, y = self:center(i)
            love.graphics.circle("fill", x, y, dot)
        end
    end

    self:drawGuides()
    self:drawBridges()
    self:drawIslands()
    self:drawRings()
    self:drawCursor()
end

function HoshiPlay:drawPanel()
    local g, x = self.game, Board.PX
    self:drawHeader(x, 46)
    local done, total = g:doneCount(), g:islandCount()
    self:drawProgress(x, 58, done / total)
    Board.drawCounter("Islands done", done .. " of " .. total, x, 82)
    Board.drawRules(x, 104, "Hoshi", RULES)

    local undo = { { input.label("l2"), "Undo" }, { input.label("r2"), "Redo" } }
    if self.drawing then
        local top = Board.drawLegend({ { { "A", "Stop drawing" } }, undo })
        theme.set("muted")
        ui.text("Move to draw a bridge. Drawing over a bridge makes two, and over two, none.",
            x, top - 74, 15, "regular", "left", Board.PW)
    else
        local top = Board.drawLegend({ { { "A", "Draw" }, { "B", "Erase" } }, undo })
        -- its own row, so its wide glyph doesn't push the columns apart
        ui.hints({ { input.pair("l1"), "Next island" } }, x, top - 32, "left", nil, 20, 1.2)
    end
end

function HoshiPlay:draw()
    self:drawBoard()
    self:drawPanel()
    self:drawConfetti()
end

return HoshiPlay
