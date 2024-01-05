const std = @import("std");

const main = @import("main.zig");
const rl = @import("raylib");
const ui = @import("ui.zig");

const Move = packed struct {
    new: bool,
    size: u2,
    from_pos: u4,
    to_pos: u4,
};

const Board = struct {
    layers: [2][3]u9,
    pieces: [2][3]u2,
    sign: u1,
    moves: i8,

    fn init() Board {
        return Board{ .layers = .{
            .{ 0, 0, 0 },
            .{ 0, 0, 0 },
        }, .pieces = .{ .{ 2, 2, 2 }, .{ 2, 2, 2 } }, .sign = 0, .moves = 0 };
    }

    fn signTopView(self: Board, sign: u1) u9 {
        return self.layers[sign][0] & ~self.layers[~sign][1] | self.layers[sign][1] & ~self.layers[~sign][2] | self.layers[sign][2];
    }

    fn sameView(self: Board, size: u2) u9 {
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

    fn biggerView(self: Board, size: u2) u9 {
        return switch (size) {
            0 => self.layers[0][1] | self.layers[1][1] |
                self.layers[0][2] | self.layers[1][2],
            1 => self.layers[0][2] | self.layers[1][2],
            2 => 0,
            3 => unreachable,
        };
    }

    fn isNewLeft(self: Board, sign: u1, size: u2) bool {
        return self.pieces[sign][size] != 0;
    }

    fn isMovable(self: Board, sign: u1, size: u2, pos: u4) bool {
        var move = self.layers[sign][size] & (@as(u9, 1) << pos);
        return move & ~self.biggerView(size) != 0;
    }

    fn isFree(self: Board, size: u2, pos: u4) bool {
        return (@as(u9, 1) << pos) & self.sameView(size) == 0;
    }

    /// 0-2=size 3=none
    fn getTopSize(self: Board, sign: u1, pos: u4) u2 {
        var size: u2 = 0;
        while (size < 3) : (size += 1) {
            if (self.isMovable(sign, size, pos)) break;
        }
        return size;
    }

    /// 0=none 1=win 2=loss 3=draw
    fn getState(self: Board) u2 {
        var win = checkView(self.signTopView(self.sign));
        var loss = checkView(self.signTopView(~self.sign));
        var score = @intFromBool(win) | (@intFromBool(loss) << 1);
        return score;
    }

    fn checkView(view: u9) bool {
        // vertical
        var check = view & (view << 1) & (view << 2) & 0b100100100;
        // diag 1
        check |= view & (view << 2) & (view << 4) & 0b000000100;
        // horizontal
        check |= view & (view << 3) & (view << 6);
        // diag 2
        check |= view & (view << 4) & (view << 8);

        return check != 0;
    }

    fn getKey(self: *Board) u48 {
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
                        piece_count |= pos + 1;
                    }
                }
                key <<= 8;
                key += piece_count;
            }
        }
        return key;
    }

    fn doNewMove(self: *Board, size: u2, to_pos: u4) void {
        self.pieces[self.sign][size] -= 1;
        self.layers[self.sign][size] |= (@as(u9, 1) << to_pos);
        self.sign = ~self.sign;
        self.moves += 1;
    }

    fn doBoardMove(self: *Board, size: u2, from_pos: u4, to_pos: u4) void {
        self.pieces[self.sign][size] ^= (@as(u9, 1) << from_pos);
        self.layers[self.sign][size] |= (@as(u9, 1) << to_pos);
        self.sign = ~self.sign;
        self.moves += 1;
    }

    fn undoNewMove(self: *Board, size: u2, to_pos: u4) void {
        self.moves -= 1;
        self.sign = ~self.sign;
        self.layers[self.sign][size] ^= (@as(u9, 1) << to_pos);
        self.pieces[self.sign][size] += 1;
    }

    fn undoBoardMove(self: *Board, size: u2, from_pos: u4, to_pos: u4) void {
        self.moves -= 1;
        self.sign = ~self.sign;
        self.layers[self.sign][size] ^= (@as(u9, 1) << to_pos);
        self.layers[self.sign][size] |= (@as(u9, 1) << from_pos);
    }

    fn doMove(self: *Board, move: Move) void {
        // From
        switch (move.new) {
            true => self.pieces[self.sign][move.size] -= 1,
            false => self.layers[self.sign][move.size] ^= (@as(u9, 1) << move.from_pos),
        }
        // To
        self.layers[self.sign][move.size] |= (@as(u9, 1) << move.to_pos);

        self.sign = ~self.sign;
        self.moves += 1;
    }

    fn undoMove(self: *Board, move: Move) void {
        self.moves -= 1;
        self.sign = ~self.sign;

        // From
        switch (move.new) {
            true => self.pieces[self.sign][move.size] += 1,
            false => self.layers[self.sign][move.size] |= (@as(u9, 1) << move.from_pos),
        }
        // To
        self.layers[self.sign][move.size] ^= (@as(u9, 1) << move.to_pos);
    }

    fn getMoves(self: *const Board, buf: *[42]Move) u8 {
        var len: u8 = 0;
        var size: u2 = 0;
        var size_view: u9 = 0;

        while (size < 3) : (size += 1) {
            // New
            if (self.pieces[self.sign][size] != 0) {
                self.addMoves(true, size, undefined, buf, &len);
            }
            // Board
            var moveable = self.layers[self.sign][2 - size] & ~size_view;
            var from_pos: u4 = 0;
            while (from_pos < 9) : (from_pos += 1) {
                if (moveable & (@as(u9, 1) << from_pos) != 0) {
                    self.addMoves(false, 2 - size, from_pos, buf, &len);
                }
            }
            size_view |= self.layers[self.sign][2 - size] | self.layers[~self.sign][2 - size];
        }

        return len;
    }

    fn addMoves(self: *const Board, new: bool, size: u2, from_pos: u4, buf: *[42]Move, len: *u8) void {
        var to_pos: u4 = 0;
        var bigger_view: u24 = undefined;
        while (to_pos < 9) : (to_pos += 1) {
            bigger_view = self.biggerView(size);
            if (bigger_view & (@as(u9, 1) << to_pos) == 0) {
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
};

const Selection = struct {
    const State = enum {
        none,
        from,
        both,
    };

    state: State,
    move: Move,

    fn init() Selection {
        return Selection{
            .state = .none,
            .move = undefined,
        };
    }

    fn options(self: Selection, board: Board) u9 {
        return switch (self.state) {
            .none => 0,
            .from, .both => ~board.biggerView(self.move.size),
        };
    }

    fn selectNew(self: *Selection, board: Board, size: u2) void {
        if (board.isNewLeft(board.sign, size)) {
            self.state = .from;
            self.move.new = true;
            self.move.size = size;
        }
    }

    fn selectBoard(self: *Selection, board: Board, pos: u4) void {
        switch (self.state) {
            .none => {
                var size = board.getTopSize(board.sign, pos);
                if (size != 3 and board.isMovable(board.sign, size, pos)) {
                    self.state = .from;
                    self.move.new = false;
                    self.move.size = size;
                    self.move.from_pos = pos;
                }
            },
            .from, .both => {
                if (board.isFree(self.move.size, pos)) {
                    self.state = .both;
                    self.move.to_pos = pos;
                } else {
                    self.state = .none;
                }
            },
        }
    }
};

const BoardUi = struct {
    // the radius
    const piece_radii = [3]f32{ 35, 60, 85 };

    const field_size = 200;
    const board_size = field_size * 3;
    const gap = field_size / 4;

    pos_x: i32,
    pos_y: i32,

    fn init(x: i32, y: i32) BoardUi {
        return BoardUi{
            .pos_x = x,
            .pos_y = y,
        };
    }

    fn is_clicked(x: i32, y: i32) bool {
        var mouse_x = rl.getMouseX();
        var mouse_y = rl.getMouseY();

        var is_x = mouse_x > x and mouse_x < x + field_size;
        var is_y = mouse_y > y and mouse_y < y + field_size;
        return is_x and is_y;
    }

    fn tick(self: BoardUi, board: Board, sel: *Selection) void {
        self.update(board, sel);
        self.draw(board, sel.*);
    }

    fn update(self: BoardUi, board: Board, sel: *Selection) void {
        if (!rl.isMouseButtonPressed(.mouse_button_left)) return;

        // Fields
        var x: i32 = 0;
        while (x < 3) : (x += 1) {
            var y: i32 = 0;
            while (y < 3) : (y += 1) {
                if (is_clicked(self.pos_x + field_size * x, self.pos_y + field_size * y)) {
                    sel.selectBoard(board, @intCast(x + y * 3));
                    return;
                }
            }
        }

        // Pieces
        var start_x = if (board.sign == 0) self.pos_x - (field_size + gap) else self.pos_x + (board_size + gap);
        var size: i32 = 0;
        while (size < 3) : (size += 1) {
            if (is_clicked(start_x, self.pos_y + field_size * size)) {
                sel.selectNew(board, @intCast(size));
                return;
            }
        }
        sel.state = .none;
    }

    fn draw_piece(x: i32, y: i32, sign: u1, size: u2, selected: bool) void {
        var radius = piece_radii[size];
        var color = if (sign == 0) rl.Color.green else rl.Color.red;
        var center_x = x + field_size / 2;
        var center_y = y + field_size / 2;
        rl.drawCircle(center_x, center_y, radius, color);
        rl.drawCircleLines(center_x, center_y, radius, rl.Color.black);
        if (selected) rl.drawCircle(center_x, center_y, 15, rl.Color.yellow);
    }

    fn draw(self: BoardUi, board: Board, sel: Selection) void {
        // Draw lines
        var step: i32 = 0;
        while (step < 4) : (step += 1) {
            var add = step * field_size;
            rl.drawLine(self.pos_x, self.pos_y + add, self.pos_x + board_size, self.pos_y + add, rl.Color.white);
            rl.drawLine(self.pos_x + add, self.pos_y, self.pos_x + add, self.pos_y + board_size, rl.Color.white);
        }

        // Draw fields
        var x: i32 = 0;
        while (x < 3) : (x += 1) {
            var y: i32 = 0;
            while (y < 3) : (y += 1) {
                var pos: u4 = @intCast(x + y * 3);
                var sign: u1 = 0;
                var size = board.getTopSize(sign, pos);
                if (size == 3) {
                    sign = 1;
                    size = board.getTopSize(sign, pos);
                    if (size == 3) continue;
                }
                var selected = sel.state != .none and sel.move.new == false and sel.move.from_pos == pos;
                draw_piece(self.pos_x + field_size * x, self.pos_y + field_size * y, sign, size, selected);
            }
        }

        // Draw pieces
        var signs = [2]u1{ 0, 1 };
        for (signs) |sign| {
            var start_x = if (sign == 0) self.pos_x - (field_size + gap) else self.pos_x + (board_size + gap);

            var size: u2 = 0;
            while (size < 3) : (size += 1) {
                var y = self.pos_y + @as(i32, size) * field_size;
                if (board.pieces[sign][size] > 1) {
                    draw_piece(start_x, y, sign, size, false);
                    y += 20;
                }
                if (board.pieces[sign][size] > 0) {
                    var selected = board.sign == sign and sel.state != .none and sel.move.new == true and sel.move.size == size;
                    draw_piece(start_x, y, sign, size, selected);
                }
            }
        }
    }
};

const Algo = struct {
    const Thread = std.Thread;
    const Mutex = Thread.Mutex;
    // 0.1s in nanoseconds
    const update_time = 100_000_000;

    const State = enum {
        quit,
        run,
        wait,
    };

    const Control = struct {
        state: State,
        board: Board,
        // 0=infinite
        max_depth: u6,
    };

    const Output = struct {
        state: State,
        board: Board,
        max_depth: u6,
        nodes_done: u64,
        moves: [42]Move,
        mlen: u8,
        scores: [42]i8,
        slen: u8,

        fn init(ctl: Control) Output {
            var moves: [42]Move = undefined;
            var mlen = ctl.board.getMoves(&moves);

            return Output{
                .state = ctl.state,
                .board = ctl.board,
                .max_depth = ctl.max_depth,
                .nodes_done = 0,
                .moves = moves,
                .mlen = mlen,
                .scores = undefined,
                .slen = 0,
            };
        }
    };

    const Search = struct {
        board: Board,
        max_moves: u6,
        nodes_done: u64,
        algo: *Algo,

        fn init(board: Board, max_depth: u6, algo: *Algo) Search {
            return Search{
                .algo = algo,
                .board = board,
                .max_moves = board.moves + max_depth,
                .nodes_done = 0,
            };
        }

        fn evaluate(self: *Search, a: i8, b: i8) i8 {
            var alpha = a;
            var beta = b;

            self.nodes_done += 1;
            // Sync handle every once a while
            if (self.nodes_done % 100_000 == 0) {
                self.algo.mutex.lock();
                if (self.algo.ctl != null) {
                    self.algo.mutex.unlock();
                    return -128;
                } else {
                    self.algo.out.nodes_done += self.nodes_done;
                    self.nodes_done = 0;
                    self.algo.mutex.unlock();
                }
            }

            var state = self.board.getState();
            switch (state) {
                0 => {},
                1 => return 127 - self.board.moves,
                2 => return -127 + self.board.moves,
                3 => return 0,
            }
            if (self.max_moves == self.board.moves) return 0;

            beta = @min(beta, 126 - self.board.moves);
            if (alpha >= beta) return alpha;

            // Search new moves
            const sizes = [3]u2{ 0, 1, 2 };
            for (sizes) |size| {
                if (self.board.isNewLeft(size)) {
                    var to_pos: u4 = 0;
                    while (to_pos < 9) : (to_pos += 1) {
                        if (self.board.isMovable(size, to_pos)) {
                            self.board.doNewMove(size, to_pos);
                            var score = self.negamax(-beta, -alpha);
                            self.board.undoNewMove(size, to_pos);

                            if (score == -128) return -128;
                            score = -score;

                            if (score >= beta) return score;
                            if (score > alpha) alpha = score;
                        }
                    }
                }
            }
            // Search board moves
            const sizes_rev = [3]u2{ 2, 1, 0 };
            for (sizes_rev) |size| {
                var from_pos: u4 = 0;
                while (from_pos < 9) : (from_pos += 1) {
                    if (self.board.isMovable(size, from_pos)) {
                        var to_pos: u4 = 0;
                        while (to_pos < 9) : (to_pos += 1) {
                            if (self.board.isFree(size, to_pos)) {
                                self.board.doBoardMove(size, from_pos, to_pos);
                                var score = self.negamax(-beta, -alpha);
                                self.board.undoBoardMove(size, from_pos, to_pos);

                                if (score == -128) return -128;
                                score = -score;

                                if (score >= beta) return score;
                                if (score > alpha) alpha = score;
                            }
                        }
                    }
                }
            }
            return alpha;
        }
    };

    mutex: Mutex,
    ctl: ?Control,
    out: Output,

    fn init(ctl: Control) Algo {
        return Algo{
            .mutex = Mutex{},
            .ctl = null,
            .out = Output.init(ctl),
        };
    }

    fn run(self: *Algo) void {
        var alpha = -127; // Lower bound
        var beta = 127; // Upper bound
        while (true) {
            self.mutex.lock();
            if (self.out.mlen < self.out.slen) {
                var search = Search.init(self.out.board, self.out.max_depth, self);
                search.board.doMove(self.out.moves[self.out.slen]);
                self.mutex.unlock();

                var val = search.evaluate(-beta, -alpha);
                if (val == -128) return; // -128: there's a reset from ctl
                val = -val;
                if (val > alpha) alpha = val; // Update search window

                self.mutex.lock();
                self.out.scores[self.out.slen] = -val;
                self.out.slen += 1;
                self.out.nodes_done += search.nodes_done;
                self.mutex.unlock();
            }
            // All moves done -> sync out + return
            else {
                self.out.state = .wait;
                self.mutex.unlock();
                return;
            }
        }
    }

    fn start(self: *Algo) void {
        while (true) : (std.time.sleep(update_time)) {
            // Update
            self.mutex.lock();
            if (self.ctl) |ctl| self.out = Output.init(ctl);
            var state = self.out.state;
            self.mutex.unlock();

            switch (state) {
                .quit => return,
                .run => self.run(),
                .wait => {},
            }
        }
    }
};

const AlgoUi = struct {
    pos: rl.Vector2,
    font: rl.Font,
    font_size: f32,
    tint: rl.Color,

    state: Algo.State,
    max_depth: u8,
    nodes: u64,
    moves: [42]Board.Move,
    moves_len: u8,
    scores: [42]i8,
    scores_len: u8,

    fn init(x: f32, y: f32, font: rl.Font, font_size: f32, tint: rl.Color, handle: *Algo.Handle) AlgoUi {
        var a_state: AlgoUi = undefined;
        a_state.pos = rl.Vector2.init(x, y);
        a_state.font = font;
        a_state.font_size = font_size;
        a_state.tint = tint;
        a_state.update(handle);
        return a_state;
    }

    fn update(self: *AlgoUi, handle: *Algo.Handle) void {
        handle.mutex.lock();
        self.state = handle.state;
        self.max_depth = handle.max_depth;
        self.nodes = handle.nodes;
        self.moves = handle.moves;
        self.moves_len = handle.moves_len;
        self.scores = handle.scores;
        self.scores_len = handle.scores_len;
        handle.mutex.unlock();
    }

    fn draw(self: *AlgoUi) void {
        var column_size = self.font_size + 4;
        var column_pos = self.pos;
        var buf: [16]u8 = undefined;
        var state_s = switch (self.state) {
            Algo.State.quit => "quit",
            Algo.State.wait => "wait",
            Algo.State.run => "run",
        };
        self.drawBuf(&buf, "Algo {s}:", .{state_s}, column_pos);

        column_pos.y += column_size;
        self.drawBuf(&buf, "Depth {}", .{self.max_depth}, column_pos);

        column_pos.y += column_size;
        self.drawBuf(&buf, "Nds {}", .{self.nodes}, column_pos);

        column_pos.y += column_size;
        self.drawBuf(&buf, "Moves:", .{}, column_pos);

        var i: u8 = 0;
        while (i < self.moves_len) : (i += 1) {
            if (i == 20) {
                column_pos.x += 100;
                column_pos.y -= 20 * (2 * column_size - 5);
            }
            column_pos.y += column_size;
            var move = self.moves[i];
            if (move.new) {
                self.drawBuf(&buf, "N: s{} t{}", .{ move.size, move.to_pos }, column_pos);
            } else {
                self.drawBuf(&buf, "B: s{} f{} t{}", .{ move.size, move.from_pos, move.to_pos }, column_pos);
            }
            column_pos.y += column_size - 5;
            if (i < self.scores_len) {
                var tint = self.tint;
                if (self.scores[i] > 0) {
                    self.tint = rl.Color.light_gray;
                } else if (self.scores[i] < 0) {
                    self.tint = rl.Color.dark_gray;
                }
                self.drawBuf(&buf, "Score: {}", .{self.scores[i]}, column_pos);
                self.tint = tint;
            }
        }
    }

    fn drawBuf(self: AlgoUi, buf: []u8, comptime fmt: []const u8, args: anytype, pos: rl.Vector2) void {
        for (buf) |*char| {
            char.* = ' ';
        }
        var fbs = std.io.fixedBufferStream(buf);
        std.fmt.format(fbs.writer(), fmt ++ "\x00", args) catch unreachable;
        rl.drawTextEx(self.font, buf[0 .. fbs.pos - 1 :0], pos, self.font_size, 1, self.tint);
    }
};

pub fn twoPlayer(app: *main.App) main.Scene {
    var state = main.Scene.Running;
    var board = Board.init();
    var selection = Selection.init();
    var board_ui = BoardUi.init(500, 200);

    while (state == .Running) {
        rl.beginDrawing();
        rl.clearBackground(main.bg);

        board_ui.tick(board, &selection);
        if (selection.state == .both) {
            board.doMove(selection.move);
            selection.state = .none;
        }

        if (app.back_b.tick()) state = .Menu;
        rl.endDrawing();
        if (rl.windowShouldClose()) state = .Quit;
    }

    return state;
}
