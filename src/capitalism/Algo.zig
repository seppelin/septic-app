const std = @import("std");
const Board = @import("Board.zig");
const Mutex = std.Thread.Mutex;
const update_time = 100_000_000;

pub const State = enum {
    quit,
    run,
    wait,
};

pub const Control = struct {
    state: State,
    board: Board,
    max_depth: u6,
};

pub const Handle = struct {
    mutex: Mutex,
    reset: ?Control,
    state: State,
    board: Board,
    max_depth: u6,
    nodes: u64,
    moves: [42]Move,
    moves_len: u8,
    scores: [42]i8,
    scores_len: u8,

    pub fn init(ctl: Control) Handle {
        return Handle{
            .mutex = Mutex{},
            .reset = ctl,
            .state = State.wait,
            .board = Board.init(),
            .max_depth = 0,
            .nodes = 0,
            .moves = undefined,
            .moves_len = 0,
            .scores = undefined,
            .scores_len = 0,
        };
    }

    pub fn setCtl(self: *Handle, ctl: Control) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.reset = ctl;
    }
};

const Algo = @This();

state: State,
pos: Pos,
max_depth: u6,
nodes: u64,
moves: [42]Move,
moves_len: u8,
scores: [42]i8,
scores_len: u8,
handle: *Handle,

fn update(self: *Algo) void {
    self.handle.mutex.lock();
    defer self.handle.mutex.unlock();
    if (self.handle.reset) |ctl| {
        self.state = ctl.state;
        self.pos = Pos.fromBoard(ctl.board);
        self.max_depth = ctl.max_depth;

        self.nodes = 0;
        self.moves_len = self.pos.getMoves(&self.moves);
        self.scores = undefined;
        self.scores_len = 0;

        self.handle.reset = null;
        self.handle.state = ctl.state;
        self.handle.board = ctl.board;
        self.handle.max_depth = ctl.max_depth;
        self.handle.nodes = self.nodes;
        self.handle.moves = self.moves;
        self.handle.moves_len = self.moves_len;
        self.handle.scores = self.scores;
        self.handle.scores_len = self.scores_len;
    }
}

pub fn start(handle: *Handle) void {
    var self: Algo = undefined;
    self.handle = handle;

    while (true) : (std.time.sleep(update_time)) {
        self.update();
        switch (self.state) {
            .quit => return,
            .run => self.run(),
            .wait => {},
        }
    }
}

fn run(self: *Algo) void {
    // untill all moves are evaluated
    while (self.scores_len < self.moves_len) {
        // call negamax
        self.pos.doMove(self.moves[self.scores_len]);
        var val = self.negamax(-127, 127);
        self.pos.undoMove(self.moves[self.scores_len]);

        if (val != -128) {
            self.scores[self.scores_len] = -val;
            self.scores_len += 1;
            // update handle
            self.handle.mutex.lock();
            self.handle.scores[self.handle.scores_len] = -val;
            self.handle.scores_len += 1;
            self.handle.mutex.unlock();
        } else {
            // handle has a reset
            return;
        }
    }
    // Sync handle
    self.state = State.wait;
    self.handle.mutex.lock();
    self.handle.state = self.state;
    self.handle.nodes = self.nodes;
    self.handle.mutex.unlock();
}

// returns -128 if reset
fn negamax(self: *Algo, a: i8, b: i8) i8 {
    var alpha = a;
    var beta = b;

    // Sync handle
    self.nodes += 1;
    if (self.nodes % 100_000 == 0) {
        self.handle.mutex.lock();
        if (self.handle.reset) |_| {
            self.handle.mutex.unlock();
            return -128;
        } else {
            self.handle.nodes = self.nodes;
            self.handle.mutex.unlock();
        }
    }
    // Check for win/draw
    var score = self.pos.getScore();
    if (score != -128) {
        return score;
    }
    // Check if already calculated
    //score = self.p_table.get(self.pos.getKey());
    //if (score != -128) return score;
    // Return if reached max depth
    if (self.max_depth == self.pos.depth) return 0;

    // Update alpha beta search window
    if (beta > 127 - self.pos.depth) {
        beta = 127 - self.pos.depth;
        if (alpha >= beta) return beta;
    }

    var moves: [42]Move = undefined;
    var len = self.pos.getMoves(&moves);
    var i: u8 = 0;
    while (i < len) : (i += 1) {
        self.pos.doMove(moves[i]);
        var val = self.negamax(-beta, -alpha);
        self.pos.undoMove(moves[i]);

        if (val == -128) return -128;
        score = -val;

        if (score >= beta) return score;
        if (score > alpha) alpha = score;
    }
    //self.p_table.put(self.pos.getKey(), alpha);
    return alpha;
}

pub const PosTable = packed struct {
    const depth = 6;
};

pub const Move = packed struct {
    new: bool,
    size: u2,
    from_pos: u4,
    to_pos: u4,
};

const Pos = struct {
    layers: [2][3]u24,
    pieces: [2][3]u2,
    next_sign: u1,
    depth: i8,

    const shift_mask = 0b100100100100100100100100;
    // 642 840  852 741 630  876 543 210
    const move_layers = [9]u24{
        0b000001000000001000000001,
        0b000000000001000000000010,
        0b001000001000000000000100,
        0b000000000000010000001000,
        0b010010000010000000010000,
        0b000000010000000000100000,
        0b100000000000100001000000,
        0b000000000100000010000000,
        0b000100100000000100000000,
    };

    fn init() Pos {
        return Pos{ .layers = [2][3]u24{
            [3]u24{ 0, 0, 0 },
            [3]u24{ 0, 0, 0 },
        }, .pieces = [2][3]u2{ [3]u2{ 2, 2, 2 }, [3]u2{ 2, 2, 2 } }, .next_sign = 0, .depth = 0 };
    }

    fn fromBoard(board: Board) Pos {
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
        return Pos{
            .layers = layers,
            .pieces = board.pieces,
            .next_sign = board.next_sign,
            .depth = 0,
        };
    }

    fn toBoard(self: Pos) Board {
        var board = Board.init();
        // fields
        var pos: u4 = 0;
        while (pos < 9) : (pos += 1) {
            var signs = [2]u1{ 0, 1 };
            for (signs) |sign| {
                var size: u2 = 0;
                while (size < 3) : (size += 1) {
                    if (self.layers[sign][size] & move_layers[pos] != 0) {
                        board.fields[pos].pieces[size] = sign;
                    }
                }
            }
        }
        // pieces
        board.pieces = self.pieces;
        return board;
    }

    fn getKey(self: *Pos) u48 {
        var key: u48 = 0;
        var sign: u6 = 0;
        while (sign < 2) : (sign += 1) {
            var size: u6 = 0;
            while (size < 3) : (size += 1) {
                var piece_count: u8 = 0;
                var pos: u4 = 0;
                while (pos < 9) : (pos += 1) {
                    if (self.layers[sign][size] & move_layers[pos] != 0) {
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

    fn doMove(self: *Pos, move: Move) void {
        // From
        switch (move.new) {
            true => self.pieces[self.next_sign][move.size] -= 1,
            false => self.layers[self.next_sign][move.size] ^= move_layers[move.from_pos],
        }
        // To
        self.layers[self.next_sign][move.size] |= move_layers[move.to_pos];

        self.next_sign = ~self.next_sign;
        self.depth += 1;
    }

    fn undoMove(self: *Pos, move: Move) void {
        self.depth -= 1;
        self.next_sign = ~self.next_sign;

        // From
        switch (move.new) {
            true => self.pieces[self.next_sign][move.size] += 1,
            false => self.layers[self.next_sign][move.size] |= move_layers[move.from_pos],
        }
        // To
        self.layers[self.next_sign][move.size] ^= move_layers[move.to_pos];
    }

    fn getMoves(self: *const Pos, buf: *[42]Move) u8 {
        var len: u8 = 0;
        var size: u2 = 0;
        var size_view: u24 = 0;

        while (size < 3) : (size += 1) {
            // New
            if (self.pieces[self.next_sign][size] != 0) {
                self.addMoves(true, size, undefined, buf, &len);
            }
            // Board
            var moveable = self.layers[self.next_sign][2 - size] & ~size_view;
            var from_pos: u4 = 0;
            while (from_pos < 9) : (from_pos += 1) {
                if (moveable & move_layers[from_pos] != 0) {
                    self.addMoves(false, 2 - size, from_pos, buf, &len);
                }
            }
            size_view |= self.layers[self.next_sign][2 - size] | self.layers[~self.next_sign][2 - size];
        }

        return len;
    }

    fn addMoves(self: *const Pos, new: bool, size: u2, from_pos: u4, buf: *[42]Move, len: *u8) void {
        var to_pos: u4 = 0;
        var size_view: u24 = undefined;
        while (to_pos < 9) : (to_pos += 1) {
            size_view = switch (size) {
                0 => self.layers[self.next_sign][2] | self.layers[~self.next_sign][2] |
                    self.layers[self.next_sign][1] | self.layers[~self.next_sign][1] |
                    self.layers[self.next_sign][0] | self.layers[~self.next_sign][0],

                1 => self.layers[self.next_sign][2] | self.layers[~self.next_sign][2] |
                    self.layers[self.next_sign][1] | self.layers[~self.next_sign][1],

                2 => self.layers[self.next_sign][2] | self.layers[~self.next_sign][2],

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

    fn getScore(self: *const Pos) i8 {
        var edited: u2 = 0;

        var view = self.layers[self.next_sign][0] & ~self.layers[~self.next_sign][1] | self.layers[self.next_sign][1] & ~self.layers[~self.next_sign][2] | self.layers[self.next_sign][2];
        edited += @intFromBool(view & (view << 1) & (view << 2) & shift_mask != 0);

        view = self.layers[~self.next_sign][0] & ~self.layers[self.next_sign][1] | self.layers[~self.next_sign][1] & ~self.layers[self.next_sign][2] | self.layers[~self.next_sign][2];
        edited += @as(u2, @intFromBool(view & (view << 1) & (view << 2) & shift_mask != 0)) * 2;

        return switch (edited) {
            0 => -128,
            1 => 127 - self.depth,
            2 => -127 + self.depth,
            3 => 0,
        };
    }
};
