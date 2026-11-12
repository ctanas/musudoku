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
        function()
            app.settings.largeNotes = true
            app.game:fillNotes()
            return 0.2
        end,
        function() shot("07b_large_notes") end,
        function()
            app.game:clearNotes()
            app.settings.largeNotes = false
            return 0.1
        end,
        function() press("start") return 0.4 end,
        function() shot("08_pause") end,
        function() press("down", "down", "down", "down", "a") return 0.4 end,
        function() shot("09_settings") end,
        function() press("b") return 0.2 end,
        function() press("b") return 0.4 end,
        function()
            -- complete the board except one cell, then enter the last number
            local g = app.game
            app.stats[g.difficulty].streak = 2 -- so the win card shows a streak
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
        function()
            app.stats.medium.streak, app.stats.medium.bestStreak = 4, 6
            app.push("stats")
            return 0.4
        end,
        function() shot("12_stats") end,
        function() press("l2") return 0.3 end, -- round to the last page
        function() shot("12c_stats_recent") end,
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
        -- Check board (only offered while mistake checking is off): two right
        -- numbers and one wrong, placed after jumping with R1 and L1
        function()
            local g = app.game
            press("r1", "r1", "l1")
            for _ = 1, 2 do
                g.cursor = g:nextEmpty(g.cursor, 1)
                press("digit" .. g.solution[g.cursor])
            end
            g.cursor = g:nextEmpty(g.cursor, 1)
            press("digit" .. (g.solution[g.cursor] % 9 + 1))
            press("start")
            return 0.4
        end,
        function() shot("15b_pause_check") end,
        function() press("down", "down", "a") return 0.4 end,
        function() shot("15c_check_confirm") end,
        function() press("a") return 0.4 end,
        function() shot("15d_check_result") end,
        function() press("a") return 0.4 end,
        function() shot("15e_after_check") end,
        -- number-first input: R1 picks the next number, A places it
        function()
            app.settings.input = "number"
            local g = app.game
            g.cursor = g:nextEmpty(60, 1)
            press("r1")
            return 0.4
        end,
        function() shot("15f_number_first") end,
        function() press("x") return 0.4 end,
        function() shot("15g_number_first_pencil") end,
        function()
            press("x")
            app.settings.input = "cell"
            app.push("settings")
            local s = app.top()
            s.sel = 9 -- Hints, past the first eight rows
            s:scrollToSelection()
            return 0.3
        end,
        function() shot("15h_settings_scrolled") end,
        function() press("b") return 0.3 end,
        function()
            app.settings.timer = true
            app.settings.mistakes = true
            app.applySettings()
            app.saveSettings()
            app.setScene("title")
            return 2.2
        end,
        function() shot("16_title_continue") end,
        -- the daily puzzle: replacing the puzzle in progress, building, solving
        function() app.openDaily() return 0.4 end,
        function() shot("16b_daily_confirm") end,
        function() press("a") return 0.15 end,
        function() shot("16c_daily_building") return 1.5 end,
        function() shot("16d_daily_play") end,
        function()
            local g = app.game
            local last = firstEmpty(1)
            for i = 1, 81 do
                if i ~= last and not g.fixed[i] then g.values[i] = g.solution[i] g.notes[i] = 0 end
            end
            g.cursor = last
            g.mode = "pen"
            press("digit" .. g.solution[last])
            return 2.2
        end,
        function() shot("16e_daily_win") end,
        function() press("a") return 2.2 end,
        function() shot("16f_title_daily_solved") end,
        function() app.openDaily() return 0.4 end,
        function() shot("16g_daily_already_solved") end,
        function() press("a") return 0.3 end,
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
            press("a")
            return 0.8
        end,
        function() shot("22b_pack_times") end,
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
