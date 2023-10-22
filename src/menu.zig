const std = @import("std");
const rl = @import("raylib");
const main = @import("main.zig");
const ui = @import("ui.zig");

pub fn run(app: *main.App) main.Scene {
    var title = ui.Text.init(700, 200, app.game_font, "game-modes", 48, 1, rl.Color.purple);
    defer title.deinit();

    var cap_b = ui.Button.from_text(700, 300, app.game_font, "capitalism", 36, 1, rl.Color.purple);
    defer cap_b.deinit();

    while (!rl.windowShouldClose()) {
        // Drawing
        rl.beginDrawing();
        rl.clearBackground(main.bg);
        {
            app.back_b.draw();
            title.draw();
            cap_b.draw();
        }
        rl.endDrawing();

        // Update
        cap_b.update();
        app.back_b.update();

        if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
            if (cap_b.isHovered) {
                return main.Scene.Capitalism;
            }
            if (app.back_b.isHovered) {
                return main.Scene.Quit;
            }
        }
    }

    return main.Scene.Quit;
}
