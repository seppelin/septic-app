pub const Move = packed struct {
    new: bool,
    size: u2,
    from_pos: u4,
    to_pos: u4,
};

const Pos = @This();

layers: [2][3]u9,
pieces: [2][3]u2,
next_sign: u1,
moves: i8,

pub fn init() Pos {
    return Pos{ .layers = .{
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
    }, .pieces = .{ .{ 2, 2, 2 }, .{ 2, 2, 2 } }, .next_sign = 0, .moves = 0 };
}

pub fn signTopView(self: Pos, sign: u1) u9 {
    return self.layers[sign][0] & ~self.layers[~sign][1] | self.layers[sign][1] & ~self.layers[~sign][2] | self.layers[sign][2];
}

pub fn biggerView(self: Pos, size: u2) u9 {
    return switch (size) {
        0 => self.layers[0][0] | self.layers[1][0] |
            self.layers[0][1] | self.layers[1][1] |
            self.layers[0][2] | self.layers[1][2],
        1 => self.layers[0][1] | self.layers[1][1] |
            self.layers[0][2] | self.layers[1][2],
        2 => self.layers[0][2] | self.layers[1][2],
        3 => unreachable,
    };
}

pub fn getKey(self: *Pos) u48 {
    var key: u48 = 0;
    var sign: u6 = 0;
    while (sign < 2) : (sign += 1) {
        var size: u6 = 0;
        while (size < 3) : (size += 1) {
            var piece_count: u8 = 0;
            var pos: u4 = 0;
            while (pos < 9) : (pos += 1) {
                if (self.layers[sign][size] & (1 << pos) != 0) {
                    piece_count <<= 4;
                    piece_count += pos + 1;
                }
            }
            key <<= 8;
            key += piece_count;
        }
    }
    return key;
}

pub fn doMove(self: *Pos, move: Move) void {
    // From
    switch (move.new) {
        true => self.pieces[self.next_sign][move.size] -= 1,
        false => self.layers[self.next_sign][move.size] ^= (1 << move.from_pos),
    }
    // To
    self.layers[self.next_sign][move.size] |= (1 << move.to_pos);

    self.next_sign = ~self.next_sign;
    self.moves += 1;
}

pub fn undoMove(self: *Pos, move: Move) void {
    self.moves -= 1;
    self.next_sign = ~self.next_sign;

    // From
    switch (move.new) {
        true => self.pieces[self.next_sign][move.size] += 1,
        false => self.layers[self.next_sign][move.size] |= (1 << move.from_pos),
    }
    // To
    self.layers[self.next_sign][move.size] ^= (1 << move.to_pos);
}

pub fn pieceLeft(self: Pos, size: u2) bool {
    return self.pieces[self.next_sign][size] != 0;
}

pub fn getMoves(self: *const Pos, buf: *[42]Move) u8 {
    var len: u8 = 0;
    var size: u2 = 0;
    var size_view: u9 = 0;

    while (size < 3) : (size += 1) {
        // New
        if (self.pieces[self.next_sign][size] != 0) {
            self.addMoves(true, size, undefined, buf, &len);
        }
        // Board
        var moveable = self.layers[self.next_sign][2 - size] & ~size_view;
        var from_pos: u4 = 0;
        while (from_pos < 9) : (from_pos += 1) {
            if (moveable & (1 << from_pos) != 0) {
                self.addMoves(false, 2 - size, from_pos, buf, &len);
            }
        }
        size_view |= self.layers[self.next_sign][2 - size] | self.layers[~self.next_sign][2 - size];
    }

    return len;
}

fn addMoves(self: *const Pos, new: bool, size: u2, from_pos: u4, buf: *[42]Move, len: *u8) void {
    var to_pos: u4 = 0;
    var bigger_view: u24 = undefined;
    while (to_pos < 9) : (to_pos += 1) {
        bigger_view = self.biggerView(size);
        if (bigger_view & (1 << to_pos) == 0) {
            buf[len.*] = Move{
                .new = new,
                .size = size,
                .from_pos = from_pos,
                .to_pos = to_pos,
            };
            len.* += 1;
        }
    }
}

fn checkView(view: u9) u2 {
    // vertical
    var check = view & (view << 1) & (view << 2) & 0b100100100;
    // diag 1
    check |= view & 0b001010100 ^ 0b001010100;
    // diag 2
    check |= view & 0b100010001 ^ 0b100010001;
    // vorizontal
    check |= view & (view << 3) & (view << 6) & 0b0000000111;
    return @intFromBool(check != 0);
}

pub fn getScore(self: *const Pos) i8 {
    var edited = checkView(self.signTopView(self.next_sign));
    edited |= checkView(self.signTopView(~self.next_sign)) << 1;

    return switch (edited) {
        0 => -128,
        1 => 127 - self.moves,
        2 => -127 + self.moves,
        3 => 0,
    };
}
