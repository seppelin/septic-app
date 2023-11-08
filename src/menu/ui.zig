const rl = @import("raylib");
const std = @import("std");

pub fn animSine(progress: f32) f32 {
    return (@sin((progress - 0.5) * std.math.pi) + 1) / 2;
}

pub fn animLin(progress: f32) f32 {
    return progress;
}

pub fn animTan(progress: f32) f32 {
    return @tan(progress) / @tan(1.0);
}

pub fn SlideButton(comptime anim_time: comptime_float, comptime anim_len: comptime_float, comptime anim_func: fn (f32) f32) type {
    return struct {
        rect: rl.Rectangle,
        texture: rl.Texture2D,
        progress: f32,
        prog_width: f32,

        pub fn init(rect: rl.Rectangle, path: [:0]const u8) @This() {
            var img = rl.loadImage(path);
            rl.imageResize(&img, @intFromFloat(rect.width), @intFromFloat(rect.height));
            return @This(){
                .rect = rect,
                .texture = rl.loadTextureFromImage(img),
                .progress = 0,
                .prog_width = anim_func(0),
            };
        }

        pub fn tick(self: *@This(), was_pressed: bool) bool {
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
            // increse if pressed or hovered
            if (pressed or rl.checkCollisionPointRec(rl.getMousePosition(), check_rect)) {
                self.progress = @min(1, self.progress + rl.getFrameTime() / anim_time);
            } else {
                self.progress = @max(0, self.progress - rl.getFrameTime() / anim_time);
            }
            self.prog_width = anim_func(self.progress) * anim_len;
            rl.drawTexture(self.texture, @intFromFloat(self.rect.x + self.prog_width), @intFromFloat(self.rect.y), rl.Color.white);
            return pressed;
        }
    };
}
