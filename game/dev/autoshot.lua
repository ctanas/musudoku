-- Development only: plays through every screen and saves screenshots to the
-- LÖVE save directory. Run with:  MUSUDOKU_AUTOSHOT=1 love game
-- Screenshots land in ~/.local/share/love/musudoku/shots/ on Linux.

local input = require("src.input")

local M = {}

function M.start(app)
    love.filesystem.createDirectory("shots")

    local function press(...)
        for _, a in ipairs({ ... }) do input.handler(a) end
    end
    local function shot(name)
        app.requestRedraw()
        love.graphics.captureScreenshot("shots/" .. name .. ".png")
    end
    local function firstEmpty(from)
        local g = app.game
        for i = from or 1, 81 do
            if g.values[i] == 0 then return i end
        end
    end

    local steps = {
        function() return 2.2 end,
        function() shot("01_title") end,
        function() press("a") return 0.4 end,
        function() shot("02_difficulty") end,
        function() press("down", "a") return 0.08 end,
        function() shot("03_generating") return 1.5 end,
        function()
            -- a few correct numbers, one wrong number, and some notes
            local g = app.game
            local placed = 0
            for i = 1, 81 do
                if g.values[i] == 0 and placed < 6 then
                    g.cursor = i
                    press("digit" .. g.solution[i])
                    placed = placed + 1
                end
            end
            local wrongCell = firstEmpty(30)
            g.cursor = wrongCell
            press("digit" .. (g.solution[wrongCell] % 9 + 1))
            press("x")
            local noteCell = firstEmpty(40)
            g.cursor = noteCell
            press("digit2", "digit5", "digit7")
            press("x")
            g.cursor = firstEmpty(46)
            return 0.6
        end,
        function() shot("04_play") end,
        function() press("a") return 0.3 end,
        function() shot("05_pad_pen") end,
        function() press("b") app.game.cursor = firstEmpty(40) press("x", "a") return 0.3 end,
        function() shot("05b_pad_pencil_notes") end,
        function() press("b", "x", "a") return 0.3 end,
        function() press("x") return 0.3 end,
        function() shot("06_pad_pencil") end,
        function() press("b", "select") return 0.6 end,
        function() shot("07_notes") end,
        function() press("start") return 0.4 end,
        function() shot("08_pause") end,
        function() press("down", "down", "down", "a") return 0.4 end,
        function() shot("09_settings") end,
        function() press("b") return 0.2 end,
        function() press("b") return 0.4 end,
        function()
            -- complete the board except one cell, then enter the last number
            local g = app.game
            local last = firstEmpty(1)
            for i = 1, 81 do
                if i ~= last and not g.fixed[i] then g.values[i] = g.solution[i] g.notes[i] = 0 end
            end
            g.cursor = last
            g.mode = "pen"
            press("digit" .. g.solution[last])
            return 0.5
        end,
        function() shot("10_win_wave") return 1.4 end,
        function() shot("11_win") end,
        function() press("b") return 0.4 end,
        function() press("down", "a") return 0.4 end,
        function() shot("12_stats") end,
        function() press("b") return 0.3 end,
        function()
            app.settings.theme = "paper"
            app.applySettings()
            app.newPuzzle("hard")
            return 1.2
        end,
        function()
            local g = app.game
            g.cursor = firstEmpty(20)
            press("select", "right", "right")
            return 0.5
        end,
        function() shot("13_paper") end,
        function()
            app.settings.theme = "chalkboard"
            app.applySettings()
            app.game.cursor = firstEmpty(30)
            press("a")
            return 0.4
        end,
        function() shot("14_chalkboard_pad") end,
        function()
            app.settings.theme = "cyanotype"
            app.settings.timer = false
            app.settings.mistakes = false
            app.applySettings()
            press("b")
            return 0.3
        end,
        function() shot("15_no_timer") end,
        function()
            app.settings.timer = true
            app.settings.mistakes = true
            app.applySettings()
            app.saveSettings()
            app.setScene("title")
            return 2.2
        end,
        function() shot("16_title_continue") end,
        -- puzzle packs
        function() app.push("packs") return 0.4 end,
        function() shot("17_packs") end,
        function()
            local s = app.top()
            for k, f in ipairs(s.files) do if f.name == "Classic collection" then s.sel = k end end
            press("a")
            return 1.0
        end,
        function() shot("18_pack") end,
        function() press("down", "down", "right", "right", "right") return 0.3 end,
        function() shot("19_pack_choose") end,
        function() press("a") return 0.6 end,
        function() shot("20_pack_play") end,
        function()
            local g = app.game
            local last = firstEmpty(1)
            for i = 1, 81 do
                if i ~= last and not g.fixed[i] then g.values[i] = g.solution[i] g.notes[i] = 0 end
            end
            g.cursor = last
            g.mode = "pen"
            press("digit" .. g.solution[last])
            return 2.0
        end,
        function() shot("21_pack_win") end,
        function() press("a") return 1.2 end,
        function() shot("22_pack_next") end,
        function()
            app.setScene("title")
            app.push("packs")
            local s = app.top()
            for k, f in ipairs(s.files) do if f.name == "Broken" then s.sel = k end end
            press("a")
            return 0.8
        end,
        function() press("down", "down", "a") return 0.4 end,
        function() shot("23_pack_broken") end,
        function()
            os.execute("mkdir -p /tmp/musudoku-empty-packs")
            require("src.packs").override = "/tmp/musudoku-empty-packs"
            app.setScene("title")
            app.push("packs")
            return 0.4
        end,
        function() shot("24_packs_empty") end,
        function()
            require("src.packs").override = nil
            app.setScene("title")
            return 2.2
        end,
        function() shot("25_title_packs") end,
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
