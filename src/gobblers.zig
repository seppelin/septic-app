const main = @import("main.zig");
const rl = @import("raylib");
const ui = @import("ui.zig");
const std = @import("std");

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
        }, .pieces = .{ .{ 2, 2, 2 }, .{ 2, 2, 2 } }, .next_sign = 0, .moves = 0 };
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
        var move = self.layers[sign][size] & (1 << pos);
        return move & ~self.biggerView(size) != 0;
    }

    fn isFree(self: Board, size: u2, pos: u4) bool {
        return (1 << pos) & self.sameView(size) == 0;
    }

    /// 0-2=size 3=none
    fn getTopSize(self: Board, sign: u1, pos: u4) u2 {
        var size = 0;
        while (size < 3) : (size += 1) {
            if (self.isMovable(sign, size, pos)) break;
        }
        return size;
    }

    /// 0=none 1=win 2=loss 3=draw
    fn getState(self: Board) u2 {
        var win: u2 = @intFromBool(checkView(self.signTopView(self.sign)));
        var loss: u2 = @intFromBool(checkView(self.signTopView(~self.sign)));
        return win | (loss << 1);
    }

    fn checkView(view: u9) bool {
        // vertical
        var check = view & (view << 1) & (view << 2) & 0b100100100;
        // vorizontal
        check |= view & (view << 3) & (view << 6);
        // diag 1
        check |= view & 0b001010100 ^ 0b001010100;
        // diag 2
        check |= view & 0b100010001 ^ 0b100010001;

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
                        piece_count += pos + 1;
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
        self.layers[self.sign][size] |= (1 << to_pos);
        self.sign = ~self.sign;
        self.moves += 1;
    }

    fn doBoardMove(self: *Board, size: u2, from_pos: u4, to_pos: u4) void {
        self.pieces[self.sign][size] ^= (1 << from_pos);
        self.layers[self.sign][size] |= (1 << to_pos);
        self.sign = ~self.sign;
        self.moves += 1;
    }

    fn undoNewMove(self: *Board, size: u2, to_pos: u4) void {
        self.moves -= 1;
        self.sign = ~self.sign;
        self.layers[self.sign][size] ^= (1 << to_pos);
        self.pieces[self.sign][size] += 1;
    }

    fn undoBoardMove(self: *Board, size: u2, from_pos: u4, to_pos: u4) void {
        self.moves -= 1;
        self.sign = ~self.sign;
        self.layers[self.sign][size] ^= (1 << to_pos);
        self.layers[self.sign][size] |= (1 << from_pos);
    }

    fn doMove(self: *Board, move: Move) void {
        // From
        switch (move.new) {
            true => self.pieces[self.sign][move.size] -= 1,
            false => self.layers[self.sign][move.size] ^= (1 << move.from_pos),
        }
        // To
        self.layers[self.sign][move.size] |= (1 << move.to_pos);

        self.sign = ~self.sign;
        self.moves += 1;
    }

    fn undoMove(self: *Board, move: Move) void {
        self.moves -= 1;
        self.sign = ~self.sign;

        // From
        switch (move.new) {
            true => self.pieces[self.sign][move.size] += 1,
            false => self.layers[self.sign][move.size] |= (1 << move.from_pos),
        }
        // To
        self.layers[self.sign][move.size] ^= (1 << move.to_pos);
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
                if (moveable & (1 << from_pos) != 0) {
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
            .state = .null,
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
        if (board.isNewLeft(size)) {
            self.state = .from;
            self.move.new = true;
            self.move.size = 2;
        }
    }

    fn selectBoard(self: *Selection, board: Board, pos: u4) void {
        switch (self.state) {
            .none => {
                var size = board.getTopSize(board.sign, pos);

                if (board.isMovable(size, pos)) {
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
    pos_x: i32,
    pos_y: i32,

    fn init(x: i32, y: i32) BoardUi {
        return BoardUi{
            .pos_x = x,
            .pos_y = y,
        };
    }

    pub fn update_click(self: BoardUi, board: *Board) void {
        var mouse_x = rl.getMouseX();
        var mouse_y = rl.getMouseY();
        // Fields
        if (mouse_x >= self.pos_x and mouse_y >= self.pos_y) {
            var index_x: u4 = 0;
            var index_y: u4 = 0;

            while (index_x < 3) : (index_x += 1) {
                if (self.pos_x + (@as(i32, index_x) + 1) * 200 >= mouse_x) {
                    break;
                }
            }
            while (index_y < 3) : (index_y += 1) {
                if (self.pos_y + (@as(i32, index_y) + 1) * 200 >= mouse_y) {
                    break;
                }
            }
            if (index_x < 3 and index_y < 3) {
                board.select(Board.Position{ .board = index_x + index_y * 3 });
                return;
            }
        }
        // Pieces
        var start_x = if (board.sign == 0) self.pos_x - 250 else self.pos_x + 650;

        if (mouse_x >= start_x and mouse_y >= self.pos_y and mouse_x <= start_x + 200) {
            var piece_size: u2 = 0;
            while (piece_size < 3) : (piece_size += 1) {
                if (mouse_y <= self.pos_y + (@as(i32, piece_size) + 1) * 200) {
                    board.select(Board.Position{ .new = piece_size });
                    return;
                }
            }
        }
        board.selected = null;
    }

    pub fn draw(self: BoardUi, board: Board) void {
        // Draw lines
        var step: i32 = 0;
        while (step < 4) : (step += 1) {
            var add = step * 200;
            rl.drawLine(self.pos_x, self.pos_y + add, self.pos_x + 600, self.pos_y + add, rl.Color.white);
            rl.drawLine(self.pos_x + add, self.pos_y, self.pos_x + add, self.pos_y + 600, rl.Color.white);
        }

        // Draw fields
        var index_x: u8 = 0;
        while (index_x < 3) : (index_x += 1) {
            var index_y: u8 = 0;
            while (index_y < 3) : (index_y += 1) {
                var index = index_x + 3 * index_y;

                if (board.fields[index].getLast()) |piece| {
                    var color = if (piece.sign == 0) rl.Color.green else rl.Color.red;
                    var size: f32 = @floatFromInt(35 + @as(i32, piece.size) * 25);

                    var center_x = self.pos_x + 200 * @as(i32, index_x) + 100;
                    var center_y = self.pos_y + 200 * @as(i32, index_y) + 100;

                    rl.drawCircle(center_x, center_y, size, color);
                    rl.drawCircleLines(center_x, center_y, size, rl.Color.black);

                    if (board.selected != null and
                        !board.selected.?.from_pos.isNew() and
                        board.selected.?.from_pos.board == index)
                    {
                        rl.drawCircle(center_x, center_y, 15, rl.Color.yellow);
                    }
                }
            }
        }

        // Draw pieces
        var signs = [2]u1{ 0, 1 };
        for (signs) |sign| {
            var center_x = if (sign == 0) self.pos_x - 150 else self.pos_x + 750;
            var color = if (sign == 0) rl.Color.green else rl.Color.red;

            var piece_size: u8 = 0;
            while (piece_size < 3) : (piece_size += 1) {
                if (board.pieces[sign][piece_size] > 0) {
                    var center_y = self.pos_y + 200 * @as(i32, piece_size) + 100;
                    var size: f32 = @floatFromInt(35 + @as(i32, piece_size) * 25);

                    rl.drawCircle(center_x, center_y, size, color);
                    rl.drawCircleLines(center_x, center_y, size, rl.Color.black);

                    if (board.pieces[sign][piece_size] > 1) {
                        center_y += 10;

                        rl.drawCircle(center_x, center_y, size, color);
                        rl.drawCircleLines(center_x, center_y, size, rl.Color.black);
                    }

                    if (board.selected != null and
                        board.selected.?.from_pos.isNew() and
                        board.selected.?.from_pos.new == piece_size and
                        board.selected.?.piece.sign == sign)
                    {
                        rl.drawCircle(center_x, center_y, 15, rl.Color.yellow);
                    }
                }
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
    _ = app;
    // Init

    return main.Scene.Quit;
}
