const rl = @import("raylib");
const menu = @import("menu.zig");
const gobblers = @import("gobblers.zig");
const ui = @import("ui.zig");

pub const icon_data = @embedFile("septic_icon.png");
pub const font_data = @embedFile("intuitive.ttf");
pub const info_font_data = @embedFile("Lato-Regular.ttf");

pub const bg = rl.Color{
    .r = 48,
    .g = 50,
    .b = 52,
    .a = 1,
};

pub const Scene = enum {
    Running,
    Menu,
    Gobblers,
    Quit,
};

pub var font: rl.Font = undefined;
pub var info_font: rl.Font = undefined;

pub fn main() !void {
    rl.initWindow(1600, 900, "septic");
    defer rl.closeWindow();

    var icon = rl.loadImageFromMemory(".png", icon_data);
    rl.setWindowIcon(icon);
    rl.unloadImage(icon);
    rl.setTargetFPS(60);

    font = rl.loadFontFromMemory(".ttf", font_data, 32, null);
    info_font = rl.loadFontFromMemory(".ttf", info_font_data, 32, null);

    var scene = Scene.Menu;

    while (true) {
        scene = switch (scene) {
            Scene.Menu => menu.run(),
            Scene.Gobblers => gobblers.twoPlayer(),
            else => break,
        };
    }
}
