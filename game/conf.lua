function love.conf(t)
    t.version = "11.5"
    t.identity = "musudoku"
    t.console = false

    t.window.title = "muSudoku"
    t.window.width = 720
    t.window.height = 480
    t.window.resizable = false
    t.window.vsync = 1
    t.window.highdpi = true -- sharp text on Retina Macs; no effect on handhelds

    t.modules.joystick = true
    t.modules.audio = true
    t.modules.sound = true
    t.modules.mouse = false
    t.modules.touch = false
    t.modules.physics = false
    t.modules.video = false
    t.modules.thread = false
end
