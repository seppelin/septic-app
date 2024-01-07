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

    fn init() Board {
        return Board{ .layers = .{
            .{ 0, 0, 0 },
            .{ 0, 0, 0 },
        }, .pieces = .{ .{ 2, 2, 2 }, .{ 2, 2, 2 } }, .sign = 0 };
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
        var win: u2 = @intFromBool(checkView(self.signTopView(self.sign)));
        var loss: u2 = @intFromBool(checkView(self.signTopView(~self.sign)));
        return win | loss << 1;
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
    }

    fn doBoardMove(self: *Board, size: u2, from_pos: u4, to_pos: u4) void {
        self.layers[self.sign][size] ^= (@as(u9, 1) << from_pos);
        self.layers[self.sign][size] |= (@as(u9, 1) << to_pos);
        self.sign = ~self.sign;
    }

    fn undoNewMove(self: *Board, size: u2, to_pos: u4) void {
        self.sign = ~self.sign;
        self.layers[self.sign][size] ^= (@as(u9, 1) << to_pos);
        self.pieces[self.sign][size] += 1;
    }

    fn undoBoardMove(self: *Board, size: u2, from_pos: u4, to_pos: u4) void {
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
    }

    fn undoMove(self: *Board, move: Move) void {
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
        depth: u7,

        fn init(state: State, board: Board, depth: u7) Control {
            return Control{
                .state = state,
                .board = board,
                .depth = depth,
            };
        }
    };

    const Output = struct {
        state: State,
        board: Board,
        depth: u7,
        nodes: u64,
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
                .depth = ctl.depth,
                .nodes = 0,
                .moves = moves,
                .mlen = mlen,
                .scores = undefined,
                .slen = 0,
            };
        }
    };

    const Search = struct {
        algo: *Algo,
        board: Board,
        depth: u7,
        nodes: u64,

        fn init(algo: *Algo, board: Board, depth: u7) Search {
            return Search{
                .algo = algo,
                .board = board,
                .depth = depth,
                .nodes = 0,
            };
        }

        fn negamax(self: *Search, a: i8, b: i8) i8 {
            var alpha = a;
            var beta = b;

            self.nodes += 1;
            // Sync algo every once a while
            if (self.nodes % 100_000 == 0) {
                self.algo.mutex.lock();
                if (self.algo.ctl != null) {
                    self.algo.mutex.unlock();
                    return -128;
                } else {
                    self.algo.out.nodes = self.nodes;
                    self.algo.mutex.unlock();
                }
            }

            var state = self.board.getState();
            switch (state) {
                0 => {},
                1 => return self.depth + 1,
                2 => return self.depth + 1,
                3 => return 0,
            }
            if (self.depth == 0) return 0;

            if (beta > self.depth + 1) {
                beta = self.depth + 1;
                if (alpha >= beta) return alpha;
            }

            // Search new moves
            const sizes = [3]u2{ 0, 1, 2 };
            for (sizes) |size| {
                if (self.board.isNewLeft(self.board.sign, size)) {
                    var to_pos: u4 = 0;
                    while (to_pos < 9) : (to_pos += 1) {
                        if (self.board.isMovable(self.board.sign, size, to_pos)) {
                            self.board.doNewMove(size, to_pos);
                            self.depth -= 1;
                            var score = self.negamax(-beta, -alpha);
                            self.depth += 1;
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
                    if (self.board.isMovable(self.board.sign, size, from_pos)) {
                        var to_pos: u4 = 0;
                        while (to_pos < 9) : (to_pos += 1) {
                            if (self.board.isFree(size, to_pos)) {
                                self.board.doBoardMove(size, from_pos, to_pos);
                                self.depth -= 1;
                                var score = self.negamax(-beta, -alpha);
                                self.depth += 1;
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

    fn setCtl(self: *Algo, ctl: Control) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.ctl = ctl;
    }

    fn run(self: *Algo) void {
        var alpha: i8 = -127; // Lower bound
        var beta: i8 = 127; // Upper bound
        self.mutex.lock();
        var search = Search.init(self, self.out.board, self.out.depth);
        self.mutex.unlock();

        if (search.board.getState() != 0 or search.depth == 0) return;
        search.depth -= 1;

        while (true) {
            self.mutex.lock();
            if (self.out.slen < self.out.mlen) {
                search.board.doMove(self.out.moves[self.out.slen]);
                self.mutex.unlock();

                var score = search.negamax(-beta, -alpha);
                if (score == -128) return; // -128: there's a reset from ctl
                score = -score;
                if (score > alpha) alpha = score; // Update search window

                self.mutex.lock();
                search.board.undoMove(self.out.moves[self.out.slen]);
                self.out.scores[self.out.slen] = score;
                self.out.slen += 1;
                self.out.nodes = search.nodes;
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
    spacing: f32,
    tint: rl.Color,
    out: Algo.Output,

    fn init(x: i32, y: i32, font: rl.Font, font_size: f32, spacing: f32, tint: rl.Color, algo: *Algo) AlgoUi {
        algo.mutex.lock();
        defer algo.mutex.unlock();
        return AlgoUi{
            .pos = rl.Vector2{ .x = @floatFromInt(x), .y = @floatFromInt(y) },
            .font = font,
            .font_size = font_size,
            .spacing = spacing,
            .tint = tint,
            .out = algo.out,
        };
    }

    fn draw(self: *AlgoUi) void {
        var pos = self.pos;
        var column_size = self.font_size + 2;
        var buf: [32]u8 = undefined;

        var state_str = switch (self.out.state) {
            .quit => "quit",
            .wait => "wait",
            .run => "run",
        };

        self.drawBuf(&buf, "State {s}, Nodes {}, Depth {}", .{ state_str, self.out.nodes, self.out.depth });

        var i: u8 = 0;
        while (i < self.out.mlen) : (i += 1) {
            self.pos.y += column_size;
            if (self.pos.y > 850) {
                self.pos.y = pos.y + column_size;
                self.pos.x += 100;
            }
            var move = self.out.moves[i];
            if (move.new) {
                self.drawBuf(&buf, "New: s{}, t{}", .{ move.size, move.to_pos });
            } else {
                self.drawBuf(&buf, "Board: s{}, f{}, t{}", .{ move.size, move.from_pos, move.to_pos });
            }
            if (i < self.out.slen) {
                self.pos.y += column_size - 4;

                var tint = self.tint;
                if (self.out.scores[i] > 0) {
                    self.tint = rl.Color.light_gray;
                } else if (self.out.scores[i] < 0) {
                    self.tint = rl.Color.dark_gray;
                }
                self.drawBuf(&buf, "Score: {}", .{self.out.scores[i]});
                self.tint = tint;
            }
        }
        self.pos = pos;
    }

    fn drawBuf(self: AlgoUi, buf: []u8, comptime fmt: []const u8, args: anytype) void {
        for (buf) |*char| {
            char.* = ' ';
        }
        var fbs = std.io.fixedBufferStream(buf);
        std.fmt.format(fbs.writer(), fmt ++ "\x00", args) catch unreachable;
        rl.drawTextEx(self.font, buf[0 .. fbs.pos - 1 :0], self.pos, self.font_size, 1, self.tint);
    }

    fn tick(self: *AlgoUi, algo: *Algo) void {
        algo.mutex.lock();
        self.out = algo.out;
        algo.mutex.unlock();

        self.draw();
    }
};

pub fn twoPlayer() main.Scene {
    var state = main.Scene.Running;
    var back = ui.Button.from_text(10, 10, main.font, "Back", 32, 1, rl.Color.red);
    
    var board = Board.init();
    var sel = Selection.init();
    var b_ui = BoardUi.init(500, 200);

    var ctl = Algo.Control.init(.run, board, 7);
    var algo = Algo.init(ctl);
    var a_thread = std.Thread.spawn(.{}, Algo.start, .{&algo}) catch unreachable;
    defer {
        ctl.state = .quit;
        algo.setCtl(ctl);
        a_thread.join();
    }
    var a_ui = AlgoUi.init(1350, 30, main.info_font, 16, 1, rl.Color.purple, &algo);

    while (state == .Running) {
        rl.beginDrawing();
        rl.clearBackground(main.bg);
        b_ui.tick(board, &sel);
        if (sel.state == .both) {
            board.doMove(sel.move);
            sel.state = .none;
        }
        a_ui.tick(&algo);
        if (back.tick()) state = .Menu;

        rl.endDrawing();
        if (rl.windowShouldClose()) state = .Quit;
    }

    return state;
}
