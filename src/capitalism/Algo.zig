const std = @import("std");
const GameBoard = @import("Board.zig");
const Mutex = std.Thread.Mutex;
const Algo = @This();

// Fields
board: Board,
next_sign: u1,
moves: [42]Move,
scores: [42]i8,
len: u8,

depth: i8,
nodes: u64,

running: bool,

in: *Control,
state: *State,

pub fn spaw(g_board: GameBoard, next_sign: u1, ctl: *Control, state: *State) std.Thread.SpawnError!std.Thread {
    var algo = init(g_board, next_sign, ctl, state);
    return std.Thread.spawn(.{}, run, .{algo});
}

pub fn init(g_board: GameBoard, next_sign: u1, ctl: *Control, state: *State) Algo {
    var algo = Algo{
        .board = Board.from_game_board(g_board),
        .next_sign = next_sign,
        .moves = undefined,
        .len = undefined,

        .scores = undefined,
        .nodes = 0,

        .depth = 0,
        .running = false,

        .in = ctl,
        .state = state,
    };
    algo.len = algo.board.getMoves(next_sign, &algo.moves);
    for (&algo.scores) |*score| {
        score.* = 0;
    }
    state.mutex.lock();
    state.moves = algo.moves;
    state.scores = algo.scores;
    state.len = algo.len;
    state.depth = @intCast(algo.depth);
    state.nodes = algo.nodes;
    state.running = algo.running;
    state.mutex.unlock();
    return algo;
}

pub fn run(s: Algo) void {
    var self = s;
    outer: while (true) : (std.time.sleep(100_000_000)) {
        if (!self.in.isEmpty()) {
            // Reset
            for (&self.scores) |*score| {
                score.* = 0;
            }
            self.nodes = 0;
            // Update
            var in_buf: [8]Control.Msg = undefined;
            var in_len = self.in.getAll(&in_buf);
            var i: u8 = 0;
            while (i < in_len) : (i += 1) {
                switch (in_buf[i]) {
                    .move => |m| {
                        self.board.doMove(self.next_sign, m);
                        self.next_sign = ~self.next_sign;
                        self.len = self.board.getMoves(self.next_sign, &self.moves);
                    },
                    .depth => |d| self.depth = @intCast(d),
                    .running => |r| self.running = r,
                    .quit => break :outer,
                }
            }
        }
        // Run algo
        if (self.running) {
            var i: u8 = 0;
            while (i < self.len) {
                var node = Node{
                    .board = self.board,
                    .next_sign = ~self.next_sign,
                    .depth = 1,
                };
                node.board.doMove(self.next_sign, self.moves[i]);
                if (self.negamax(&node)) |score| {
                    self.scores[i] = score;

                    self.state.mutex.lock();
                    self.state.scores[i] = score;
                    self.state.mutex.unlock();
                }
                // Changes to algo -> restart algo
                else {
                    continue :outer;
                }
            }
            self.running = false;
        }
    }
}

fn negamax(self: *Algo, node: *Node) ?i8 {
    if (self.nodes % 100_000 == 0) {
        if (!self.in.isEmpty()) {
            return null;
        }
        self.state.mutex.lock();
        self.state.nodes = self.nodes;
        self.state.mutex.unlock();
    }

    var win = node.board.checkWin();
    if (win[node.next_sign]) {
        if (win[~node.next_sign]) {
            return 0;
        }
        return std.math.maxInt(i8) - node.depth;
    }
    if (win[~node.next_sign]) {
        return std.math.minInt(i8) + node.depth;
    }
    if (node.depth == self.depth) {
        return 0;
    }

    var best_score: i8 = 0;
    var moves: [42]Move = undefined;
    var len = node.board.getMoves(node.next_sign, &moves);
    var i: u8 = 0;
    while (i < len) : (i += 1) {
        self.nodes += 1;
        node.board.doMove(node.next_sign, moves[i]);
        node.next_sign = ~node.next_sign;
        node.depth += 1;

        if (negamax(self, node)) |score| {
            best_score = @max(best_score, -score);
        } else {
            return null;
        }

        node.depth -= 1;
        node.next_sign = ~node.next_sign;
        node.board.undoMove(node.next_sign, moves[i]);
    }
    return best_score;
}

pub const Control = struct {
    pub const Msg = union(enum) {
        depth: u8,
        move: Move,
        running: bool,
        quit: void,
    };

    mutex: Mutex,
    queue: [8]Msg,
    len: u8,

    pub fn init() Control {
        return Control{
            .queue = undefined,
            .len = 0,
            .mutex = Mutex{},
        };
    }

    pub fn getAll(self: *Control, buf: *[8]Msg) u8 {
        self.mutex.lock();
        buf.* = self.queue;
        var len = self.len;
        self.len = 0;
        self.mutex.unlock();
        return len;
    }

    pub fn put(self: *Control, item: Msg) void {
        self.mutex.lock();
        self.queue[self.len] = item;
        self.len += 1;
        self.mutex.unlock();
    }

    pub fn isEmpty(self: *Control) bool {
        self.mutex.lock();
        var empty = (self.len == 0);
        self.mutex.unlock();
        return empty;
    }

    pub fn isFull(self: *Control) bool {
        self.mutex.lock();
        var full = (self.len == self.queue.len);
        self.mutex.unlock();
        return full;
    }
};

pub const State = struct {
    mutex: Mutex,

    moves: [42]Move,
    scores: [42]i8,
    len: u8,

    depth: u8,
    nodes: u64,

    running: bool,

    pub fn init() State {
        return State{
            .mutex = Mutex{},
            .moves = undefined,
            .scores = undefined,
            .len = 0,
            .depth = 0,
            .nodes = 0,
            .running = false,
        };
    }
};

const Node = struct {
    board: Board,
    next_sign: u1,
    depth: i8,
};

pub const Move = packed struct {
    new: bool,
    size: u2,
    from_pos: u4,
    to_pos: u4,
};

const Board = struct {
    layers: [2][3]u24,
    pieces: [2][3]u2,

    // 012 345 678  036 147 258  048 246
    const move_layers = [9]u24{
        0b100000000100000000100000,
        0b010000000000100000000000,
        0b001000000000000100000100,
        0b000100000010000000000000,
        0b000010000000010000010010,
        0b000001000000000010000000,
        0b000000100001000000000001,
        0b000000010000001000000000,
        0b000000001000000001001000,
    };

    fn init() Board {
        return Board{ .layers = [2][3]u24{
            [3]u24{ 0, 0, 0 },
            [3]u24{ 0, 0, 0 },
        }, .pieces = [2]u6{ 0b111111, 0b111111 } };
    }

    fn from_game_board(board: GameBoard) Board {
        var layers = [2][3]u24{
            [3]u24{ 0, 0, 0 },
            [3]u24{ 0, 0, 0 },
        };
        for (board.fields, 0..) |field, i| {
            var size: u2 = 0;
            while (size < 3) : (size += 1) {
                if (field.pieces[size]) |sign| {
                    layers[sign][size] |= move_layers[i];
                }
            }
        }
        return Board{
            .layers = layers,
            .pieces = board.pieces,
        };
    }

    fn doMove(self: *Board, sign: u1, move: Move) void {
        // From
        switch (move.new) {
            true => self.pieces[sign][move.size] -= 1,
            false => self.layers[sign][move.size] ^= move_layers[move.from_pos],
        }
        // To
        self.layers[sign][move.size] |= move_layers[move.to_pos];
    }

    fn undoMove(self: *Board, sign: u1, move: Move) void {
        // From
        switch (move.new) {
            true => self.pieces[sign][move.size] += 1,
            false => self.layers[sign][move.size] |= move_layers[move.from_pos],
        }
        // To
        self.layers[sign][move.size] ^= move_layers[move.to_pos];
    }

    fn getMoves(self: *const Board, sign: u1, buf: *[42]Move) u8 {
        var len: u8 = 0;
        var size: u2 = 0;
        var size_view: u24 = 0;

        while (size < 3) : (size += 1) {
            // New
            if (self.pieces[sign][size] != 0) {
                self.addMoves(true, sign, size, undefined, buf, &len);
            }
            // Board
            var moveable = self.layers[sign][2 - size] & ~size_view;
            var from_pos: u4 = 0;
            while (from_pos < 9) : (from_pos += 1) {
                if (moveable & move_layers[from_pos] != 0) {
                    self.addMoves(false, sign, 2 - size, from_pos, buf, &len);
                }
            }
            size_view |= self.layers[sign][2 - size] | self.layers[~sign][2 - size];
        }

        return len;
    }

    fn addMoves(self: *const Board, new: bool, sign: u1, size: u2, from_pos: u4, buf: *[42]Move, len: *u8) void {
        var to_pos: u4 = 0;
        var size_view: u24 = undefined;
        while (to_pos < 9) : (to_pos += 1) {
            size_view = switch (size) {
                0 => self.layers[sign][2] | self.layers[~sign][2] |
                    self.layers[sign][1] | self.layers[~sign][1] |
                    self.layers[sign][0] | self.layers[~sign][0],

                1 => self.layers[sign][2] | self.layers[~sign][2] |
                    self.layers[sign][1] | self.layers[~sign][1],

                2 => self.layers[sign][2] | self.layers[~sign][2],

                else => unreachable,
            };

            if (size_view & move_layers[to_pos] == 0) {
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

    fn checkWin(self: *const Board) [2]bool {
        var win = [2]bool{ false, false };
        var view: u24 = undefined;

        var signs = [2]u1{ 0, 1 };
        for (signs) |sign| {
            view = self.layers[sign][0] & ~self.layers[~sign][1] | self.layers[sign][1] & ~self.layers[~sign][2] | self.layers[sign][2];
            win[sign] = view & (view << 1) & (view << 2) != 0;
        }

        return win;
    }
};

test "Sizes" {
    std.debug.print("Algo: {}\n", .{@sizeOf(Algo)});
    std.debug.print("Algo in: {}\n", .{@sizeOf(Control)});
    std.debug.print("Algo state: {}\n", .{@sizeOf(State)});
    std.debug.print("Algo move: {}\n", .{@sizeOf(Move)});
    std.debug.print("Algo board: {}\n", .{@sizeOf(Board)});
    std.debug.print("Algo node: {}\n", .{@sizeOf(Node)});
}

test "Board move" {
    var board = Board.init();
    var buf: [42]Move = undefined;
    var len = board.getMoves(0, &buf);
    try std.testing.expectEqual(len, (9 + 9 + 9));

    var move = Move{
        .new = true,
        .size = 1,
        .from_pos = undefined,
        .to_pos = 0,
    };
    board.doMove(0, move);
    len = board.getMoves(0, &buf);
    try std.testing.expectEqual(len, 8 + (8 + 8 + 9));

    move = Move{
        .new = true,
        .size = 2,
        .from_pos = undefined,
        .to_pos = 1,
    };
    board.doMove(0, move);
    len = board.getMoves(0, &buf);
    try std.testing.expectEqual(len, 7 + 8 + (7 + 7 + 8));

    move = Move{
        .new = false,
        .size = 2,
        .from_pos = 1,
        .to_pos = 0,
    };
    board.doMove(0, move);
    len = board.getMoves(0, &buf);
    try std.testing.expectEqual(len, 8 + (8 + 8 + 8));

    move = Move{
        .new = true,
        .size = 1,
        .from_pos = undefined,
        .to_pos = 1,
    };
    board.doMove(0, move);
    len = board.getMoves(0, &buf);
    try std.testing.expectEqual(len, 8 + 7 + (7 + 8));

    move = Move{
        .new = false,
        .size = 2,
        .from_pos = 0,
        .to_pos = 2,
    };
    board.doMove(0, move);
    var win = board.checkWin();
    try std.testing.expectEqual(win[0], true);
    try std.testing.expectEqual(win[1], false);

    move = Move{
        .new = true,
        .size = 2,
        .from_pos = undefined,
        .to_pos = 0,
    };
    board.doMove(1, move);
    len = board.getMoves(0, &buf);
    try std.testing.expectEqual(len, 6 + 7 + (6 + 7));
    len = board.getMoves(1, &buf);
    try std.testing.expectEqual(len, 7 + (6 + 6 + 7));
}
