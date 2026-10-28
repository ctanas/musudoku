-- Development only: captures the completion effects mid-animation.
-- Run with:  MUSUDOKU_FXSHOTS=1 love game   (screenshots go to shots/fx_*.png)

local input = require("src.input")
local sudoku = require("src.sudoku")

local M = {}

function M.start(app)
    love.filesystem.createDirectory("shots")
    local function shot(name)
        app.requestRedraw()
        love.graphics.captureScreenshot("shots/fx_" .. name .. ".png")
    end
    local function fillAllBut(cells, keep)
        local g = app.game
        for _, j in ipairs(cells) do
            if j ~= keep and not g.fixed[j] then g.values[j], g.notes[j] = g.solution[j], 0 end
        end
    end
    local function placeLast(i)
        local g = app.game
        g.cursor, g.mode = i, "pen"
        input.handler("digit" .. g.solution[i])
    end
    local function emptyIn(cells)
        for _, j in ipairs(cells) do
            if app.game.values[j] == 0 then return j end
        end
    end

    local steps = {
        function() app.newPuzzle("easy") return 1.5 end,
        -- a box
        function()
            local box = sudoku.UNITS[19 + 4]
            local last = emptyIn(box)
            fillAllBut(box, last)
            placeLast(last)
            return 0.14
        end,
        function() shot("1_box_early") return 0.16 end,
        function() shot("2_box_mid") return 1.0 end,
        -- a row and a box at once
        function()
            local row = sudoku.UNITS[1]
            local box = sudoku.UNITS[19]
            local last
            for _, j in ipairs(row) do
                if app.game.values[j] == 0 and sudoku.BOX[j] == 0 then last = j break end
            end
            if last then
                fillAllBut(row, last)
                fillAllBut(box, last)
                placeLast(last)
            end
            return 0.3
        end,
        function() shot("3_row_and_box") return 1.0 end,
        -- all nine of one digit
        function()
            local g = app.game
            local d, last
            for i = 1, 81 do
                if g.values[i] == 0 then d, last = g.solution[i], i break end
            end
            local cells = {}
            for i = 1, 81 do if g.solution[i] == d then cells[#cells + 1] = i end end
            fillAllBut(cells, last)
            placeLast(last)
            return 0.3
        end,
        function() shot("4_digit") return 1.0 end,
        -- the whole puzzle
        function()
            local all = {}
            for i = 1, 81 do all[i] = i end
            local last = emptyIn(all)
            fillAllBut(all, last)
            placeLast(last)
            return 0.35
        end,
        function() shot("5_win_wave") return 0.25 end,
        function() shot("6_win_confetti") return 0.35 end,
        function() shot("7_win_confetti_late") return 1.4 end,
        function() shot("8_win_card") return 0.3 end,
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
