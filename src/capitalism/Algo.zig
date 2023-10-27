const std = @import("std");
const GameBoard = @import("Board.zig");
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const update_time = 100_000_000;

pub const State = enum {
    quit,
    run,
    wait,
};

pub const Handle = struct {
    mutex: Mutex,

    reload: bool,
    state: State,
    board: Board,
    max_depth: u6,

    nodes: u64,
    moves: [42]Move,
    moves_len: u8,
    scores: [42]i8,
    scores_len: u8,

    pub fn init(g_board: GameBoard) Handle {
        return Handle{
            .mutex = Mutex{},
            .reload = false,
            .state = State.wait,
            .board = Board.fromGBoard(g_board),
            .max_depth = 0,
            .nodes = 0,
            .moves = undefined,
            .moves_len = 0,
            .scores = undefined,
            .scores_len = 0,
        };
    }
};

pub fn spawn(handle: *Handle) Thread.SpawnError!Thread {
    return Thread.spawn(.{}, Algo.start, .{handle});
}

const Algo = struct {
    state: State,
    board: Board,
    max_depth: u6,
    nodes: u64,
    moves: [42]Move,
    moves_len: u8,
    scores: [42]i8,
    scores_len: u8,
    handle: *Handle,

    fn start(handle: *Handle) void {
        var self = Algo.fromHandle(handle);

        while (true) : (std.time.sleep(update_time)) {
            self.update();
            switch (self.state) {
                .quit => return,
                .run => self.run(),
                .wait => {},
            }
        }
    }

    fn fromHandle(handle: *Handle) Algo {
        handle.mutex.lock();
        var algo = Algo{
            .state = handle.state,
            .board = handle.board,
            .max_depth = handle.max_depth,
            .nodes = handle.nodes,
            .moves = handle.moves,
            .moves_len = handle.moves_len,
            .scores = handle.scores,
            .scores_len = handle.scores_len,
            .handle = handle,
        };
        handle.mutex.unlock();
        return algo;
    }

    fn update(self: *Algo) void {
        self.handle.mutex.lock();
        if (self.handle.reload) {
            self.state = self.handle.state;
            self.board = self.handle.board;
            self.max_depth = self.handle.max_depth;

            self.nodes = 0;
            self.moves_len = self.board.getMoves(&self.moves);
            self.scores_len = 0;

            self.handle.nodes = self.nodes;
            self.handle.moves = self.moves;
            self.handle.moves_len = self.moves_len;
            self.handle.scores_len = self.scores_len;
            self.handle.reload = false;
        }
        self.handle.mutex.unlock();
    }

    fn run(self: *Algo) void {
        var i: u8 = 0;
        while (i < self.moves_len) : (i += 1) {
            self.board.doMove(self.moves[i]);
            var val = self.negamax();
            self.board.undoMove(self.moves[i]);

            if (val) |score| {
                self.handle.mutex.lock();
                self.scores[self.scores_len] = -score;
                self.scores_len += 1;
                self.handle.scores[self.handle.scores_len] = -score;
                self.handle.scores_len += 1;
                self.handle.mutex.unlock();
            } else {
                return;
            }
        }
        self.state = State.wait;
        self.handle.mutex.lock();
        self.handle.state = self.state;
        self.handle.nodes = self.nodes;
        self.handle.mutex.unlock();
    }
    // returns null if reload
    fn negamax(self: *Algo) ?i8 {
        self.nodes += 1;
        if (self.nodes % 100_000 == 0) {
            self.handle.mutex.lock();

            if (self.handle.reload) {
                self.handle.mutex.unlock();
                return null;
            } else {
                self.handle.nodes = self.nodes;
                self.handle.mutex.unlock();
            }
        }

        if (self.board.getScore()) |score| return score;
        if (self.board.depth == self.max_depth) return 0;

        var best_score: i8 = undefined;
        var moves: [42]Move = undefined;
        var len = self.board.getMoves(&moves);

        // Init best score
        self.board.doMove(moves[0]);
        var val = self.negamax();
        self.board.undoMove(moves[0]);
        if (val) |score| best_score = -score else return null;

        var i: u8 = 1;
        while (i < len) : (i += 1) {
            self.board.doMove(moves[i]);
            val = self.negamax();
            self.board.undoMove(moves[i]);

            if (val) |score| {
                best_score = @max(best_score, -score);
            } else {
                return null;
            }
        }
        return best_score;
    }
};

pub const Move = packed struct {
    new: bool,
    size: u2,
    from_pos: u4,
    to_pos: u4,

    pub fn from_sel(sel: GameBoard.Selected) Move {
        var move: Move = undefined;
        move.size = sel.piece.size;
        move.to_pos = sel.to_pos.?;
        switch (sel.from_pos) {
            .new => move.new = true,
            .board => |from_pos| {
                move.new = false;
                move.from_pos = from_pos;
            },
        }
        return move;
    }
};

pub const Board = struct {
    layers: [2][3]u24,
    pieces: [2][3]u2,
    next_sign: u1,
    depth: i8,

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
        }, .pieces = [2][3]u2{ [3]u2{ 2, 2, 2 }, [3]u2{ 2, 2, 2 } } };
    }

    pub fn fromGBoard(board: GameBoard) Board {
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
            .next_sign = board.next_sign,
            .depth = 0,
        };
    }

    fn doMove(self: *Board, move: Move) void {
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

    fn undoMove(self: *Board, move: Move) void {
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

    fn getMoves(self: *const Board, buf: *[42]Move) u8 {
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

    fn addMoves(self: *const Board, new: bool, size: u2, from_pos: u4, buf: *[42]Move, len: *u8) void {
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

    fn getScore(self: *const Board) ?i8 {
        var win = self.checkWin();
        if (win[self.next_sign]) {
            if (win[~self.next_sign]) {
                return 0;
            }
            return 126 - self.depth;
        }
        if (win[~self.next_sign]) {
            return -126 + self.depth;
        }
        return null;
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
