const rl = @import("raylib");
const std = @import("std");

pub const MenuSelect = struct {
    const anim_time = 0.5;
    const anim_len = 50;
    const State = enum {
        start,
        increase,
        decrease,
        end,
    };
    pos: rl.Vector2,
    rect: rl.Rectangle,
    text: rl.Texture,
    increase: bool,
    progress: f32,

    pub fn tick(self: *MenuSelect, pressed: *bool) void {
        self.increase = pressed | rl.checkCollisionPointRec(rl.getMousePosition(), self.rect);
        if (self.increase) {
            self.progress = @min(0.5, self.progress + rl.getFrameTime() / anim_time);
        } else {
            self.progress = @max(0, self.progress - rl.getFrameTime() / anim_time);
        }
        self.rect.x = self.pos.x + @sin(self.progress) * anim_len;
        rl.drawTexture(self.text, @intFromFloat(self.rect.x), @intFromFloat(self.rect.y), rl.Color.white);
    }
};
