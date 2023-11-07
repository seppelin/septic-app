const std = @import("std");
const rl = @import("raylib");
const main = @import("main.zig");
const ui = @import("ui.zig");
const m_ui = @import("menu/ui.zig");

pub fn run(app: *main.App) main.Scene {
    var title = ui.Text.init(700, 200, app.info_font, "game-modes", 48, 1, rl.Color.purple);
    defer title.deinit();
    var gobblers_b = ui.Button.from_text(700, 300, app.game_font, "gobblers", 36, 1, rl.Color.purple);
    defer gobblers_b.deinit();

    defer rl.endDrawing();
    while (!rl.windowShouldClose()) {
        // Drawing
        rl.beginDrawing();
        rl.clearBackground(main.bg);
        {
            if (app.back_b.tick()) return main.Scene.Quit;
            if (gobblers_b.tick()) return main.Scene.Gobblers;
            title.draw();
        }
        rl.endDrawing();
    }
    return main.Scene.Quit;
}
