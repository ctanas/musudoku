-- Development only: screenshots of explained hints.
-- Run with:  MUSUDOKU_HINTSHOTS=1 love game   (shots/hint_*.png)

local input = require("src.input")
local hints = require("src.hints")

local M = {}

function M.start(app)
    love.filesystem.createDirectory("shots")
    local function shot(name)
        app.requestRedraw()
        love.graphics.captureScreenshot("shots/hint_" .. name .. ".png")
    end
    local function press(...) for _, a in ipairs({ ... }) do input.handler(a) end end

    -- Advance a hard puzzle with plain placements until the next hint needs
    -- at least one elimination step first.
    local function seekMultiStep()
        local g = app.game
        for _ = 1, 81 do
            local found = hints.search(g.values, g.solution, g.fixed)
            if found.steps and #found.steps > 1 then return true end
            if not found.steps then return false end
            local s = found.steps[#found.steps]
            g.values[s.cell], g.notes[s.cell] = s.digit, 0
        end
        return false
    end

    local steps = {
        function()
            app.settings.hints = "explained"
            app.newPuzzle("easy")
            return 1.4
        end,
        function() press("y") return 0.3 end,
        function() shot("1_simple") end,
        function() press("a") return 0.5 end,
        function() shot("2_after_place") return 0.8 end,
        function()
            local g = app.game
            for i = 1, 81 do
                if g.values[i] == 0 then
                    g.cursor = i
                    press("digit" .. (g.solution[i] % 9 + 1))
                    break
                end
            end
            press("y")
            return 0.3
        end,
        function() shot("3_mistake") end,
        function() press("a") return 0.4 end,
        function() app.newPuzzle("hard") return 1.6 end,
        function()
            for _ = 1, 20 do
                if seekMultiStep() then break end
                app.startGame(require("src.sudoku").generate("hard"), "hard")
            end
            press("select") -- fill notes so "Remove from notes" shows
            press("y")
            return 0.3
        end,
        function() shot("4_elimination") end,
        function() press("a") return 0.3 end,
        function() shot("5_after_elimination") end,
        function()
            app.settings.theme = "paper"
            app.applySettings()
            return 0.3
        end,
        function() shot("6_paper") end,
        function()
            app.settings.theme = "cyanotype"
            app.applySettings()
        end,
    }

    local origUpdate = love.update
    local t, idx, waitUntil = 0, 1, 0
    love.update = function(dt)
        origUpdate(dt)
        t = t + dt
        if t >= waitUntil then
            if idx <= #steps then
                local step = steps[idx]
                idx = idx + 1
                waitUntil = t + (step() or 0.15)
            else
                love.event.quit()
            end
        end
    end
end

return M
