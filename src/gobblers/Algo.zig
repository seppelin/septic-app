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
board: Board,
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
        self.board = ctl.board;
        self.max_depth = ctl.max_depth;

        self.nodes = 0;
        self.moves_len = self.board.getMoves(&self.moves);
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
    if (self.max_depth == self.pos.depth) return 0;

    // Update alpha beta search window
    if (beta > 127 - self.pos.depth) {
        beta = 127 - self.pos.depth;
        if (alpha >= beta) return beta;
    }

    // Search moves
    var bigger: u24 = 0;
    const sizes = [2]u2{ 2, 1, 0 };
    for (sizes) |size| {
        if (self.board.pieceLeft(size)) {
            var to_pos: u4 = 0;
            while (to_pos < 9) : (to_pos += 1) {
                if ()
            }
        }
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
    return alpha;
}
