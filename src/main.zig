const rl = @import("raylib");
const menu = @import("menu.zig");
const cap = @import("capitalism.zig");
const ui = @import("ui.zig");

pub const bg = rl.Color{
    .r = 48,
    .g = 50,
    .b = 52,
    .a = 1,
};

pub const Scene = enum {
    Menu,
    Capitalism,
    Quit,
};

pub const App = struct {
    game_font: rl.Font,
    info_font: rl.Font,
    icon: rl.Image,
    back_b: ui.Button,

    fn init() App {
        var icon = rl.loadImage("assets/septic_small.png");
        return App{
            .game_font = rl.loadFont("assets/intuitive.ttf"),
            .info_font = rl.loadFont("assets/Lato-Regular.ttf"),
            .icon = icon,
            .back_b = ui.Button.init(icon, 10, 10, 50, 50),
        };
    }

    fn deinit(self: *App) void {
        rl.unloadFont(self.game_font);
        rl.unloadFont(self.info_font);
        rl.unloadImage(self.icon);
        self.back_b.deinit();
    }
};

pub fn main() !void {
    rl.initWindow(1600, 900, "septic");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    var app = App.init();
    defer app.deinit();

    var scene = Scene.Menu;

    while (true) {
        scene = switch (scene) {
            Scene.Menu => menu.run(&app),
            Scene.Capitalism => cap.twoPlayer(&app),
            Scene.Quit => break,
        };
    }
}
