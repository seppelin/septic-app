const rl = @import("raylib");
const std = @import("std");

pub const MenuSelect = struct {
    const anim_time = 100_000_000;
    const AnimState = enum {
        start,
        increase,
        decrease,
        end,
    };

    pos: rl.Vector2,
    rect: rl.Rectangle,
    text: rl.Texture,
    a_state: AnimState,
    a_time: u32,

    pub fn tick(self: *MenuSelect) bool {
        _ = self;
        var m_pos = rl.getMousePosition();
        _ = m_pos;
    }
};
