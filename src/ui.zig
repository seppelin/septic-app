const std = @import("std");
const rl = @import("raylib");

pub const Button = struct {
    texture: rl.Texture2D,
    rects: [2]rl.Rectangle,
    isHovered: bool,

    pub fn init(image: rl.Image, x: i32, y: i32, width: i32, height: i32) Button {
        var resize_img = rl.imageCopy(image);
        defer rl.unloadImage(resize_img);

        rl.imageResize(&resize_img, width, height);

        var texture = rl.loadTextureFromImage(resize_img);
        rl.setTextureFilter(texture, 1);

        var rect = rl.Rectangle{
            .x = @floatFromInt(x),
            .y = @floatFromInt(y),
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
        };

        var p_rect = rl.Rectangle{
            .x = rect.x - rect.width * 0.05,
            .y = rect.y - rect.height * 0.05,
            .width = rect.width * 1.1,
            .height = rect.height * 1.1,
        };

        return Button{
            .texture = texture,
            .rects = [2]rl.Rectangle{ rect, p_rect },
            .isHovered = false,
        };
    }

    pub fn from_text(x: i32, y: i32, font: rl.Font, text: [:0]const u8, fontSize: f32, spacing: f32, tint: rl.Color) Button {
        // Create Image
        var size = rl.measureTextEx(font, text, fontSize, spacing);
        var img = rl.genImageColor(@intFromFloat(size.x + 10), @intFromFloat(size.y + 10), rl.Color.blank);
        defer rl.unloadImage(img);

        rl.imageDrawTextEx(&img, font, text, rl.Vector2{ .x = 5, .y = 5 }, fontSize, spacing, tint);

        // Draw rect
        rl.imageDrawLine(&img, 0, 0, img.width - 1, 0, tint);
        rl.imageDrawLine(&img, 0, 0, 0, img.height - 1, tint);
        rl.imageDrawLine(&img, img.width - 1, 0, img.width - 1, img.height - 1, tint);
        rl.imageDrawLine(&img, 0, img.height - 1, img.width - 1, img.height - 1, tint);

        return init(img, x, y, img.width, img.height);
    }

    pub fn deinit(b: Button) void {
        rl.unloadTexture(b.texture);
    }

    pub fn update_click(self: *Button) void {
        self.isHovered = rl.checkCollisionPointRec(rl.getMousePosition(), self.rects[@intFromBool(self.isHovered)]);
    }

    pub fn draw(self: Button) void {
        if (self.isHovered) {
            var pos = rl.Vector2.init(self.rects[1].x, self.rects[1].y);
            rl.drawTextureEx(self.texture, pos, 0.0, 1.1, rl.Color.white);
        } else {
            var pos = rl.Vector2.init(self.rects[0].x, self.rects[0].y);
            rl.drawTextureEx(self.texture, pos, 0.0, 1.0, rl.Color.white);
        }
    }
};

pub const Text = struct {
    texture: rl.Texture2D,
    posX: i32,
    posY: i32,

    pub fn init(x: i32, y: i32, font: rl.Font, text: [:0]const u8, fontSize: f32, spacing: f32, tint: rl.Color) Text {
        var img = rl.imageTextEx(font, text, fontSize, spacing, tint);
        defer rl.unloadImage(img);

        return Text{
            .texture = rl.loadTextureFromImage(img),
            .posX = x,
            .posY = y,
        };
    }

    pub fn deinit(self: Text) void {
        rl.unloadTexture(self.texture);
    }

    pub fn draw(self: Text) void {
        rl.drawTexture(self.texture, self.posX, self.posY, rl.Color.white);
    }
};

pub const DynText = struct {
    font: rl.Font,
    text: [:0]const u8,
    position: rl.Vector2,
    f_size: f32,
    spacing: f32,
    tint: rl.Color,

    pub fn init(x: i32, y: i32, font: rl.Font, text: [:0]const u8, f_size: f32, spacing: f32, tint: rl.Color) DynText {
        var position = rl.Vector2{
            .x = @floatFromInt(x),
            .y = @floatFromInt(y),
        };
        return DynText{
            .font = font,
            .text = text,
            .position = position,
            .f_size = f_size,
            .spacing = spacing,
            .tint = tint,
        };
    }

    pub fn draw(self: DynText) void {
        rl.drawTextEx(self.font, self.text, self.position, self.f_size, self.spacing, self.tint);
    }
};

pub fn TextInputSized(comptime max_size: comptime_int, comptime valid_fn: anytype) type {
    return struct {
        const spacing = 1;
        const a_diff = 20;

        rect: rl.Rectangle,
        pos: rl.Vector2,
        text: [max_size + 1]u8,
        len: u8,
        f_size: f32,
        font: rl.Font,
        tint: rl.Color,
        active: bool,

        pub fn init(x: f32, y: f32, f_size: f32, font: rl.Font, tint: rl.Color) @This() {
            var pos = rl.Vector2.init(x, y);
            var m_text: [max_size + 1]u8 = undefined;
            var i: u8 = 0;
            while (i < max_size) : (i += 1) {
                m_text[i] = 'W';
            }
            m_text[max_size] = '\x00';
            var size = rl.measureTextEx(font, m_text[0..max_size :0], f_size, spacing);
            var off_x = size.x * 0.1;
            var off_y = size.y * 0.1;

            var self = @This(){
                .rect = rl.Rectangle{
                    .x = pos.x - off_x / 2,
                    .y = pos.y - off_y / 2,
                    .width = size.x + off_x,
                    .height = size.y + off_y,
                },
                .pos = pos,
                .text = undefined,
                .len = 0,
                .f_size = f_size,
                .font = font,
                .tint = tint,
                .active = false,
            };
            self.tint.a = if (self.tint.a < a_diff) 0 else self.tint.a - 25;
            self.text[self.len] = '\x00';
            return self;
        }

        pub fn draw(self: @This()) void {
            rl.drawRectangleLinesEx(self.rect, 3, self.tint);
            rl.drawTextEx(self.font, self.text[0..self.len :0], self.pos, self.f_size, spacing, self.tint);
        }

        pub fn update(self: *@This()) void {
            // Mouse
            if (rl.checkCollisionPointRec(rl.getMousePosition(), self.rect)) {
                rl.setMouseCursor(@intFromEnum(rl.MouseCursor.mouse_cursor_ibeam));
                if (rl.isMouseButtonDown(rl.MouseButton.mouse_button_left)) self.active = !self.active;
                if (self.active) self.tint.a += a_diff else self.tint.a -= a_diff;
            } else {
                rl.setMouseCursor(@intFromEnum(rl.MouseCursor.mouse_cursor_default));
            }
            // Keys
            var key = rl.getCharPressed();
            while (key != 0 and self.len != max_size) : (key = rl.getCharPressed()) {
                if (valid_fn(key)) {
                    self.text[self.len] = @intCast(key);
                    self.len += 1;
                    self.text[self.len] = '\x00';
                }
            }
            if (rl.isKeyPressed(rl.KeyboardKey.key_backspace) and self.len != 0) {
                self.len -= 1;
                self.text[self.len] = '\x00';
            }
        }
    };
}

pub fn valid_nums(char: i32) bool {
    return (char >= '0' and char <= '9');
}
