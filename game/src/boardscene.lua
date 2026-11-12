-- Shared parts of the Solo, Pairlink and Hoshi play screens: the board's
-- layout and grid, the sliding cursor, the side panel's header, rules and
-- button legend, undo and redo, pausing, and the celebration when a puzzle is
-- solved. scenes/soloplay.lua, scenes/pairplay.lua and scenes/hoshiplay.lua
-- build on it.

local ui = require("src.ui")
local theme = require("src.theme")
local sound = require("src.sound")

local Board = {}
Board.__index = Board

local AREA = 450              -- the board fits a square this size at (15, 15)
local PX, PW = 488, 217       -- side panel
Board.PX, Board.PW = PX, PW

local FLASH_TIME = 0.7        -- one cell's flash
Board.FLASH_TIME = FLASH_TIME
local RING_TIME = 0.65        -- glow pulse around the board
local LIFT = 0.16             -- how far numbers bounce during a flash
local WIN_CARD_AT = 1.7       -- seconds after solving before the result card
local CONFETTI = { "accent", "user", "given", "boxLine", "note" }
local LEVEL_LABELS = { easy = { "EASY" }, medium = { "MEDIUM", "MED" }, hard = { "HARD" } }
local HEAD_LABEL, HEAD_CLOCK, HEAD_GAP = 24, 40, 10 -- header sizes and spacing

-- Makes `scene` (a table of methods) a board screen: whatever it doesn't
-- define comes from here.
function Board.extend(scene)
    scene.__index = scene
    return setmetatable(scene, { __index = Board })
end

-- Sets up `self` to show app.puzzles[kind], centered in the board area.
function Board.init(self, app, kind)
    self.app, self.kind, self.t = app, kind, 0
    local g = app.puzzles[kind]
    self.game, self.n = g, g.size
    self.cs = math.floor(AREA / g.size)
    self.bs = self.cs * g.size
    self.bx = 15 + math.floor((AREA - self.bs) / 2)
    self.by = self.bx
    self.vx, self.vy = self:cellPos(g.cursor)
    self.flash, self.rings, self.particles = {}, {}, {}
    self.shake = 0
    return self
end

function Board:cellPos(i)
    local n = self.n
    return self.bx + ((i - 1) % n) * self.cs, self.by + math.floor((i - 1) / n) * self.cs
end

function Board:rowCol(i)
    return math.floor((i - 1) / self.n), (i - 1) % self.n
end

-- The cell next to i in a direction, or nil past the edge.
function Board:neighbour(i, dr, dc)
    local r, c = self:rowCol(i)
    r, c = r + dr, c + dc
    if r < 0 or c < 0 or r >= self.n or c >= self.n then return nil end
    return r * self.n + c + 1
end

-- Actions ---------------------------------------------------------------------

-- Moves the cursor, wrapping around the edges.
function Board:move(dr, dc)
    local g = self.game
    local r, c = self:rowCol(g.cursor)
    g.cursor = ((r + dr) % self.n) * self.n + (c + dc) % self.n + 1
    sound.play("move")
end

function Board:blocked()
    self.shake = 0.25
    sound.play("blocked")
end

function Board:history(which)
    local g = self.game
    local cell
    if which == "undo" then cell = g:undo() else cell = g:redo() end
    if not cell then return self:blocked() end
    g.cursor = cell
    sound.play("erase")
    self.app.markPuzzleDirty(self.kind)
    if g:checkSolved() then self:startWin(cell) end
end

function Board:pause()
    self.hidden = true
    sound.play("open")
    self.app.savePuzzle(self.kind)
    self.app.push("pause", self.kind)
end

function Board:resume()
    self.hidden = false
end

-- Feedback --------------------------------------------------------------------

-- Cells flash in a ripple spreading from cell i.
function Board:rippleFrom(i, cells, base)
    local r0, c0 = self:rowCol(i)
    for _, j in ipairs(cells) do
        local r, c = self:rowCol(j)
        local start = self.t + (base or 0) + (math.abs(r - r0) + math.abs(c - c0)) * 0.035
        if not self.flash[j] or self.flash[j] < start then self.flash[j] = start end
    end
end

-- How much a cell's content grows while it flashes (1 when it doesn't).
function Board:flashScale(i)
    local f = self.flash[i]
    if f and self.t >= f then
        local p = (self.t - f) / FLASH_TIME
        if p <= 1 then return 1 + LIFT * math.sin(math.pi * p) end
    end
    return 1
end

function Board:ring(x, y, w, h, delay, strength)
    self.rings[#self.rings + 1] = {
        x = x, y = y, w = w, h = h,
        start = self.t + (delay or 0), strength = strength or 1,
    }
end

function Board:spawnConfetti()
    local rand = love.math.random
    for k = 1, 130 do
        local w = 6 + rand() * 6
        local side = (k % 2 == 0) and 1 or -1 -- two fountains, from the lower corners
        self.particles[#self.particles + 1] = {
            x = self.bx + self.bs / 2 + side * (self.bs / 2 - 20) + (rand() - 0.5) * 40,
            y = self.by + self.bs - 10,
            vx = -side * (90 + rand() * 300),
            vy = -480 - rand() * 380,
            rot = rand() * math.pi,
            vr = (rand() - 0.5) * 14,
            w = w, h = w * (0.45 + rand() * 0.5),
            color = CONFETTI[rand(#CONFETTI)],
            born = self.t, life = 1.1 + rand() * 0.5,
        }
    end
end

-- Solved: a wave over the board from cell i, glow pulses, confetti, then
-- the result card.
function Board:startWin(i)
    self.winT = 0
    local all = {}
    for j = 1, self.n * self.n do all[j] = j end
    self:rippleFrom(i, all, 0.1)
    self:ring(self.bx, self.by, self.bs, self.bs, 0.15, 1.6)
    self:ring(self.bx, self.by, self.bs, self.bs, 0.5, 2.4)
    self.confettiAt = self.t + 0.3
    sound.play("win")
    self.newBest = self.app.recordPuzzleSolve(self.kind)
end

-- Update ----------------------------------------------------------------------

function Board:update(dt)
    self.t = self.t + dt
    local g = self.game
    if not g.solved and self.app.focused then
        g.elapsed = g.elapsed + dt
    end

    local tx, ty = self:cellPos(g.cursor)
    local k = 1 - math.exp(-dt * 28)
    self.vx = self.vx + (tx - self.vx) * k
    self.vy = self.vy + (ty - self.vy) * k
    -- wrapping around the edge: jump, don't fly across (unless the scene sets
    -- slideFar, where the cursor never wraps and long moves are normal)
    if not self.slideFar and (math.abs(tx - self.vx) > self.cs * 3 or math.abs(ty - self.vy) > self.cs * 3) then
        self.vx, self.vy = tx, ty
    end
    if math.abs(tx - self.vx) < 0.25 and math.abs(ty - self.vy) < 0.25 then
        self.vx, self.vy = tx, ty -- settle exactly, so the scene can go idle
    end

    if self.shake > 0 then self.shake = math.max(0, self.shake - dt) end
    for i, start in pairs(self.flash) do
        if self.t > start + FLASH_TIME then self.flash[i] = nil end
    end
    for n = #self.rings, 1, -1 do
        if self.t > self.rings[n].start + RING_TIME then table.remove(self.rings, n) end
    end
    if self.confettiAt and self.t >= self.confettiAt then
        self.confettiAt = nil
        self:spawnConfetti()
    end
    for n = #self.particles, 1, -1 do
        local p = self.particles[n]
        p.vy = p.vy + 980 * dt
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        p.rot = p.rot + p.vr * dt
        if self.t > p.born + p.life or p.y > ui.H + 20 then table.remove(self.particles, n) end
    end

    -- the clock only changes once a second, so that's all it needs to draw
    local second = math.floor(g.elapsed)
    if second ~= self.lastSecond then
        self.lastSecond = second
        if self.app.settings.timer then self.app.requestRedraw() end
    end

    if self.winT then
        self.winT = self.winT + dt
        if self.winT > WIN_CARD_AT and not self.winShown then
            self.winShown = true
            self.particles = {}
            self.app.push("win", { kind = self.kind, newBest = self.newBest })
        end
    end
end

-- True while something on screen is moving and needs continuous frames.
function Board:busy()
    local tx, ty = self:cellPos(self.game.cursor)
    if tx ~= self.vx or ty ~= self.vy then return true end
    if next(self.flash) ~= nil or self.shake > 0 then return true end
    if #self.rings > 0 or #self.particles > 0 or self.confettiAt then return true end
    if self.winT and not self.winShown then return true end
    return false
end

-- Drawing: board --------------------------------------------------------------

-- The colour a flashing cell is tinted with.
function Board:flashColor(_, alpha)
    theme.set("accent", alpha)
end

-- The board: frame, surface, then `cells(x, y, i)` for every cell (inside
-- the rounded corners, for fills), flashes, and the grid lines on top.
function Board:drawSurface(cells)
    local bx, by, bs, cs, n = self.bx, self.by, self.bs, self.cs, self.n
    theme.frame(bx, by, bs, bs)
    theme.set("board")
    ui.rect("fill", bx, by, bs, bs, 8)

    love.graphics.stencil(function() ui.rect("fill", bx, by, bs, bs, 8) end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    if not self.hidden then
        for i = 1, n * n do
            local x, y = self:cellPos(i)
            cells(x, y, i)
            local f = self.flash[i]
            if f and self.t >= f then
                local p = (self.t - f) / FLASH_TIME
                if p <= 1 then
                    self:flashColor(i, math.sin(math.pi * p) * 0.6)
                    ui.rect("fill", x, y, cs, cs)
                end
            end
        end
    end
    theme.texture(bx, by, bs, bs) -- under the lines and numbers, so they stay crisp
    love.graphics.setStencilTest()

    theme.set("line")
    love.graphics.setLineWidth(1)
    for k = 1, n - 1 do
        love.graphics.line(bx + k * cs, by, bx + k * cs, by + bs)
        love.graphics.line(bx, by + k * cs, bx + bs, by + k * cs)
    end
    theme.set("boxLine")
    love.graphics.setLineWidth(3)
    ui.rect("line", bx, by, bs, bs, 8)
end

-- Text centered on (x, y), grown by `scale` around its middle.
function Board.drawText(str, x, y, size, weight, scale)
    if scale and scale ~= 1 then
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.scale(scale)
        ui.centered(str, 0, 0, size, weight, "center")
        love.graphics.pop()
    else
        ui.centered(str, x, y, size, weight, "center")
    end
end

-- Glow pulses around the board.
function Board:drawRings()
    for _, r in ipairs(self.rings) do
        local p = (self.t - r.start) / RING_TIME
        if p >= 0 and p <= 1 then
            local grow = 1 + 8 * ui.ease(p) * r.strength
            local fade = (1 - p) ^ 2
            for k = 0, 2 do
                local spread = grow + k * 3
                theme.set("accent", fade * (0.9 - k * 0.3))
                love.graphics.setLineWidth(3 - k)
                ui.rect("line", r.x - spread, r.y - spread, r.w + spread * 2, r.h + spread * 2, 6 + spread)
            end
        end
    end
end

-- The cursor, sliding between cells. `setColor` (optional) sets its colour;
-- with `halo`, a wider outline in the board's colour goes under it, so it
-- shows on a filled cell of its own colour.
function Board:drawCursor(setColor, width, halo)
    if self.winT then return end
    width = width or 3
    local dx = 0
    if self.shake > 0 then dx = math.sin(self.shake * 70) * 4 * (self.shake / 0.25) end
    local x, y, s = self.vx + 3 + dx, self.vy + 3, self.cs - 6
    if halo then
        theme.set("board")
        love.graphics.setLineWidth(width + 4)
        ui.rect("line", x, y, s, s, 6)
    end
    if setColor then setColor() else theme.set("mark") end
    love.graphics.setLineWidth(width)
    ui.rect("line", x, y, s, s, 6)
end

function Board:drawConfetti()
    for _, p in ipairs(self.particles) do
        local age = (self.t - p.born) / p.life
        local alpha = age < 0.7 and 1 or math.max(0, 1 - (age - 0.7) / 0.3)
        theme.set(p.color, alpha)
        love.graphics.push()
        love.graphics.translate(p.x, p.y)
        love.graphics.rotate(p.rot)
        love.graphics.rectangle("fill", -p.w / 2, -p.h / 2, p.w, p.h, 1, 1)
        love.graphics.pop()
    end
end

-- Drawing: side panel ---------------------------------------------------------

-- The side panel clock: 134 -> "02:14", an hour or more -> "1:02:14".
local function clock(seconds)
    seconds = math.floor(seconds)
    if seconds >= 3600 then return ui.formatTime(seconds) end
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Level and size (left) and clock (right) share the top row, on one
-- baseline. The first label that fits is used; only if none fits does the
-- row shrink.
function Board:drawHeader(x, base)
    local g = self.game
    local time = self.app.settings.timer and clock(g.elapsed)
    -- measured with its widest digits, so the label doesn't change as it ticks
    local clockW = time and HEAD_GAP + ui.width((time:gsub("%d", "0")), HEAD_CLOCK, "bold") or 0
    local size = " " .. g.size .. "×" .. g.size
    local label, rowW
    for _, name in ipairs(LEVEL_LABELS[g.difficulty] or { "" }) do
        label = name .. size
        rowW = ui.width(label, HEAD_LABEL, "bold") + clockW
        if rowW <= PW then break end
    end
    local k = math.min(1, (PW - 2) / rowW)
    theme.set("muted")
    ui.onBaseline(label, x, base, HEAD_LABEL * k, "bold", "left")
    if time then
        theme.set("text")
        ui.onBaseline(time, x + PW, base, HEAD_CLOCK * k, "bold", "right")
    end
end

-- A thin bar across the panel, `fraction` full.
function Board:drawProgress(x, y, fraction)
    theme.set("panel")
    ui.rect("fill", x, y, PW, 6, 3)
    theme.set("accent")
    ui.rect("fill", x, y, math.max(6, PW * fraction), 6, 3)
end

-- "Label 3" in the panel's counter style, left edge at x.
function Board.drawCounter(label, value, x, y)
    theme.set("muted")
    local w = ui.centered(label, x, y, 19, "regular", "left")
    theme.set("text")
    ui.centered(tostring(value), x + w + 6, y, 19, "bold", "left")
end

-- A card with the game's name and rules, one bullet each. Returns its bottom.
function Board.drawRules(x, y, name, rules)
    local pad, size = 12, 16
    local textW = PW - pad * 2 - 12
    local h = pad + 26
    for _, rule in ipairs(rules) do h = h + ui.wrapHeight(rule, size, "regular", textW) + 6 end
    h = h + pad - 6
    theme.set("panel")
    ui.rect("fill", x, y, PW, h, 10)
    theme.set("mark")
    ui.text(name, x + pad, y + pad, size, "bold")
    local ty = y + pad + 26
    for _, rule in ipairs(rules) do
        theme.set("muted")
        love.graphics.circle("fill", x + pad + 3, ty + size * 0.62, 2.5)
        theme.set("text", 0.88)
        ui.text(rule, x + pad + 12, ty, size, "regular", "left", textW)
        ty = ty + ui.wrapHeight(rule, size, "regular", textW) + 6
    end
    return y + h
end

-- Button legend at the bottom of the panel: rows of { button, label }.
function Board.drawLegend(rows)
    local top = 462 - (#rows - 1) * 32
    ui.legend(rows, { PX, PX + 116 }, top, 32, nil, 20, 1.2)
    return top
end

return Board
