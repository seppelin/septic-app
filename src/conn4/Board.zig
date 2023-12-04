const Board = @This();
const width = 7;
const height = 6;
const max_moves = width * height;

fields: [2]u64,
moves: u8,

pub fn init() Board {
    return Board{
        .fields = [2]u64{ 0, 0 },
        .next_sign = 0,
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
