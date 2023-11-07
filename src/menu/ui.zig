const rl = @import("raylib");
const std = @import("std");

pub const MenuSelect = struct {
    const anim_time = 0.3;
    const anim_len = 50;
    rect: rl.Rectangle,
    text: rl.Texture,
    increase: bool,
    progress: f32,
    prog_width: f32,

    pub fn init(rect: rl.Rectangle, path: [:0]const u8) MenuSelect {
        var img = rl.loadImage(path);
        rl.imageResize(&img, @intFromFloat(rect.width), @intFromFloat(rect.height));
        return MenuSelect{
            .rect = rect,
            .text = rl.loadTextureFromImage(img),
            .increase = false,
            .progress = 0,
            .prog_width = 0,
        };
    }

    pub fn tick(self: *MenuSelect, was_pressed: bool) bool {
        var check_rect = rl.Rectangle{
            .x = self.rect.x,
            .y = self.rect.y,
            .width = self.rect.width + self.prog_width,
            .height = self.rect.height,
        };
        var pressed: bool = undefined;
        if (was_pressed) {
            pressed = !rl.isMouseButtonDown(rl.MouseButton.mouse_button_left);
        } else {
            pressed = rl.isMouseButtonDown(rl.MouseButton.mouse_button_left) and rl.checkCollisionPointRec(rl.getMousePosition(), check_rect);
        }
        self.increase = pressed or rl.checkCollisionPointRec(rl.getMousePosition(), check_rect);
        if (self.increase) {
            self.progress = @min(std.math.pi / 2.0, self.progress + rl.getFrameTime() / anim_time);
        } else {
            self.progress = @max(0, self.progress - rl.getFrameTime() / anim_time);
        }
        self.prog_width = @sin(self.progress) * anim_len;
        rl.drawTexture(self.text, @intFromFloat(self.rect.x + self.prog_width), @intFromFloat(self.rect.y), rl.Color.white);
        return pressed;
    }
};
