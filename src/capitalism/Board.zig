const lines = [8][3]u8{
    [_]u8{ 0, 1, 2 },
    [_]u8{ 3, 4, 5 },
    [_]u8{ 6, 7, 8 },
    [_]u8{ 0, 3, 6 },
    [_]u8{ 1, 4, 7 },
    [_]u8{ 2, 5, 8 },
    [_]u8{ 0, 4, 8 },
    [_]u8{ 2, 4, 6 },
};

const Board = @This();

fields: [9]Field,
pieces: [2][3]u2,
next_sign: u1,
selected: ?Selected,

pub fn init() Board {
    var fields: [9]Field = undefined;
    for (&fields) |*field| {
        field.* = Field{
            .pieces = [3]?u1{ null, null, null },
        };
    }

    var pieces = [2][3]u2{
        [3]u2{ 2, 2, 2 },
        [3]u2{ 2, 2, 2 },
    };

    return Board{
        .fields = fields,
        .pieces = pieces,
        .next_sign = 0,
        .selected = null,
    };
}

pub fn isSelected(self: *Board) bool {
    return self.selected != null and self.selected.?.to_pos != null;
}

pub fn select(self: *Board, pos: Position) void {
    if (self.selected == null or pos.isNew()) {
        // New Selection
        var piece = self.getPiece(pos);
        if (piece != null and piece.?.sign == self.next_sign) {
            self.selected = Selected{
                .pos = pos,
                .piece = piece.?,
                .to_pos = null,
            };
        }
        // Clicked on empty field
        else {
            self.selected = null;
        }
    } else {
        var to_last = self.fields[pos.board].getLast();
        // Place the selected piece on a field
        if (to_last == null or to_last.?.size < self.selected.?.piece.size) {
            self.selected.?.to_pos = pos.board;
        } else {
            self.selected = null;
        }
    }
}

pub const MoveResult = enum {
    Invalid,
    Draw,
    WinTrue,
    WinFalse,
    Continue,
};

pub fn doMove(self: *Board) MoveResult {
    if (!self.isSelected()) {
        return MoveResult.Invalid;
    }
    var from = self.selected.?.pos;
    var to = self.selected.?.to_pos.?;
    var piece = self.selected.?.piece;

    // remove from
    switch (from) {
        .new => |size| self.pieces[self.next_sign][size] -= 1,
        .board => |board_pos| self.fields[board_pos].removeLast(),
    }

    // add to
    self.fields[to].add(piece);

    self.selected = null;
    self.next_sign = ~self.next_sign;

    // check win
    var win = [2]bool{ false, false };
    for (lines) |line| {
        if (self.checkLine(line)) |sign| {
            win[sign] = true;
        }
    }

    if (win[0] and win[1]) {
        return MoveResult.Draw;
    } else if (win[0]) {
        return MoveResult.WinFalse;
    } else if (win[1]) {
        return MoveResult.WinTrue;
    } else {
        return MoveResult.Continue;
    }
}

fn checkLine(self: *Board, line: [3]u8) ?u1 {
    var piece0 = self.fields[line[0]].getLast() orelse return null;
    var piece1 = self.fields[line[1]].getLast() orelse return null;
    var piece2 = self.fields[line[2]].getLast() orelse return null;
    if (piece0.sign == piece1.sign and piece0.sign == piece2.sign) {
        return piece0.sign;
    } else {
        return null;
    }
}

fn getPiece(self: *Board, pos: Position) ?Piece {
    switch (pos) {
        .new => |size| {
            if (self.pieces[self.next_sign][size] > 0) {
                return Piece{
                    .sign = self.next_sign,
                    .size = size,
                };
            } else {
                return null;
            }
        },
        .board => |board_pos| {
            return self.fields[board_pos].getLast();
        },
    }
}

pub const Field = struct {
    pieces: [3]?u1,

    pub fn getLast(self: Field) ?Piece {
        for ([3]u8{ 2, 1, 0 }) |size| {
            if (self.pieces[size]) |sign| {
                return Piece{
                    .sign = sign,
                    .size = size,
                };
            }
        }
        return null;
    }

    fn removeLast(self: *Field) void {
        for ([3]u8{ 2, 1, 0 }) |size| {
            if (self.pieces[size]) |_| {
                self.pieces[size] = null;
                return;
            }
        }
        unreachable;
    }

    fn add(self: *Field, piece: Piece) void {
        self.pieces[piece.size] = piece.sign;
    }
};

pub const Selected = struct {
    pos: Position,
    piece: Piece,
    to_pos: ?u8,
};

pub const Position = union(enum) {
    new: u8,
    board: u8,

    pub fn isNew(self: Position) bool {
        return switch (self) {
            .new => true,
            .board => false,
        };
    }
};

pub const Piece = struct {
    sign: u1,
    size: u8,
};
