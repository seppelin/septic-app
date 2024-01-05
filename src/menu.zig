const std = @import("std");
const rl = @import("raylib");
const main = @import("main.zig");
const ui = @import("ui.zig");

pub fn run(app: *main.App) main.Scene {
    var state = main.Scene.Running;

    var gobblers_b = ui.Button.from_text(700, 300, app.game_font, "gobblers", 36, 1, rl.Color.purple);
    defer gobblers_b.deinit();

    while (state == .Running) {
        rl.beginDrawing();
        rl.clearBackground(main.bg);
        {
            if (app.back_b.tick()) state = .Quit;
            if (gobblers_b.tick()) state = .Gobblers;
        }
        rl.endDrawing();
        if (rl.windowShouldClose()) state = .Quit;
    }
    return state;
}
