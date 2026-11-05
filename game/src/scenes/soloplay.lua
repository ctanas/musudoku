local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")
local input = require("src.input")
local Board = require("src.boardscene")
local SoloGame = require("src.sologame")

local SHADE, DOT = SoloGame.SHADE, SoloGame.DOT

-- The Solo play screen. boardscene.lua does the layout, cursor, pausing and
-- celebrating; this adds shading, dots and the side panel. Shaded cells are
-- black and hide their number; holding Y shows them. Numbers that still
-- repeat in their row or column are tinted (Settings → Show repeats in Solo).
local SoloPlay = Board.extend({})

local RULES = {
    "Shade cells so no number repeats in a row or column.",
    "Shaded cells may touch at corners, but not at sides.",
    "The unshaded cells form one connected area.",
}

-- Numbers still repeating in their row or column are tinted this far toward
-- the theme's error colour: a hint of what's left, not a mistake.
local REPEAT_TINT = 0.45

function SoloPlay.new(app)
    return Board.init(setmetatable({}, SoloPlay), app, "solo")
end

function SoloPlay:react(res)
    if not res.changed then return end
    self.app.markPuzzleDirty("solo")
    self.pop = { i = self.game.cursor, t = self.t }
    if res.mark == SHADE then
        sound.play("place")
    elseif res.mark == DOT then
        sound.play("note")
    else
        sound.play("erase")
    end
    if res.solved then self:startWin(self.game.cursor) end
end

function SoloPlay:action(a)
    if self.winT then return end
    local g = self.game
    if a == "start" or a == "menu" then
        self:pause()
    elseif a == "up" then self:move(-1, 0)
    elseif a == "down" then self:move(1, 0)
    elseif a == "left" then self:move(0, -1)
    elseif a == "right" then self:move(0, 1)
    elseif a == "a" then self:react(g:toggleShade(g.cursor))
    elseif a == "x" then self:react(g:toggleDot(g.cursor))
    elseif a == "b" or a == "erase" then self:react(g:clear(g.cursor))
    elseif a == "l2" then self:history("undo")
    elseif a == "r2" then self:history("redo")
    end
end

function SoloPlay:busy()
    if self.pop and self.t - self.pop.t < 0.2 then return true end
    return Board.busy(self)
end

-- Drawing ---------------------------------------------------------------------

function SoloPlay:drawBoard()
    local g, cs = self.game, self.cs
    local matching = self.app.settings.matching
    local cr, cc = self:rowCol(g.cursor)
    local cv = g.values[g.cursor]

    -- the cursor's row and column, with its number's repeats in them
    -- picked out; shaded cells are dark holes
    self:drawSurface(function(x, y, i)
        local r, c = self:rowCol(i)
        if g.marks[i] == SHADE then
            theme.set("shade")
            ui.rect("fill", x, y, cs, cs)
        elseif not self.winT and (r == cr or c == cc) then
            theme.set((matching and g.values[i] == cv) and "same" or "peer")
            ui.rect("fill", x, y, cs, cs)
        end
    end)
    if self.hidden then return end

    local size = math.floor(cs * 0.58)
    local peek = input.isDown("y")
    local repeats = self.app.settings.repeats and g:repeats() or {}
    for i = 1, self.n * self.n do
        local x, y = self:cellPos(i)
        local cx, cy = x + cs / 2, y + cs / 2
        local scale = self:flashScale(i)
        if self.pop and self.pop.i == i then
            local p = (self.t - self.pop.t) / 0.18
            if p < 1 then scale = scale * (1 + 0.22 * (1 - ui.ease(p))) end
        end
        local shaded = g.marks[i] == SHADE
        if not shaded or peek then
            if shaded then
                theme.set("shadeText", 0.75)
            elseif repeats[i] then
                theme.mix("given", "error", REPEAT_TINT)
            else
                theme.set("given")
            end
            Board.drawText(tostring(g.values[i]), cx, cy, size, "regular", scale)
        end
        if g.marks[i] == DOT then
            theme.set("mark", 0.9)
            love.graphics.setLineWidth(cs >= 60 and 3 or 2.5)
            love.graphics.circle("line", cx, cy, cs * 0.36 * scale)
        end
    end

    self:drawRings()
    self:drawCursor()
end

function SoloPlay:drawPanel()
    local g, x = self.game, Board.PX
    self:drawHeader(x, 46)
    local clear, total = g:clearLines()
    self:drawProgress(x, 58, clear / total)
    Board.drawCounter("Lines with repeats", total - clear, x, 82)
    Board.drawRules(x, 104, "Solo", RULES)
    local top = Board.drawLegend({
        { { "A", "Shade" }, { "B", "Clear" } },
        { { "X", "Keep" }, { "Y", "Peek" } },
        { { input.label("l2"), "Undo" }, { input.label("r2"), "Redo" } },
    })
    theme.set("muted")
    ui.text("Hold Y to see the numbers under shaded cells.", x, top - 60, 15, "regular", "left", Board.PW)
end

function SoloPlay:draw()
    self:drawBoard()
    self:drawPanel()
    self:drawConfetti()
end

return SoloPlay
