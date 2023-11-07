const Board = @This();
const max_moves = 7 * 6;

fields: [7][6]?bool,
next_sign: bool,
moves: u8,

pub fn init() Board {
    var fields: [7][6]?bool = undefined;
    for (&fields) |*column| {
        for (&column) |*field| {
            field.* = null;
        }
    }
    return Board{
        .fields = fields,
        .moves = 0,
    };
}

pub fn isFull(self: Board, column: u8) bool {
    return (self.fields[column][5] != null);
}

pub fn play(self: *Board, column: u8) void {
    var row = 0;
    while (self.fields[column][row] != null) : (row += 1) {}
    self.fields[column][row] = self.next_sign;
    self.next_sign = !self.next_sign;
    self.moves += 1;
}

pub const Check = enum {
    Draw,
    Win,
    None,
};

pub fn check(self: Board) Check {
    _ = self;
}
