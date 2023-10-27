const main = @import("main.zig");
const rl = @import("raylib");
const ui = @import("ui.zig");
const Board = @import("capitalism/Board.zig");
const algo = @import("capitalism/algo.zig");
const std = @import("std");
const NumIn = ui.TextInputSized(2, ui.valid_nums);

pub fn twoPlayer(app: *main.App) main.Scene {
    // Init
    var state = ui.DynText.init(700, 10, app.game_font, "Green's turn!", 36, 1, rl.Color.purple);
    var board = Board.init();
    var board_ui = BoardUi.init(500, 100);
    var num_in = NumIn.init(20, 200, 24, app.game_font, rl.Color.purple);
    var finished = false;

    // Algo init
    var a_handle = algo.Handle.init(board);
    var a_thread = algo.spawn(&a_handle) catch unreachable;
    var a_ui = AlgoUi.init(1400, 10, app.info_font, 16, rl.Color.purple, &a_handle);
    var a_update_timer = std.time.Timer.start() catch unreachable;

    // cfg algo
    a_handle.mutex.lock();
    a_handle.reload = true;
    a_handle.state = algo.State.run;
    a_handle.max_depth = 5;
    a_handle.mutex.unlock();

    defer {
        a_handle.mutex.lock();
        a_handle.reload = true;
        a_handle.state = algo.State.quit;
        a_handle.mutex.unlock();
        a_thread.join();
    }

    // Loop
    while (!rl.windowShouldClose()) {
        // Draw
        rl.beginDrawing();
        rl.clearBackground(main.bg);

        app.back_b.draw();
        board_ui.draw(board);
        state.draw();
        a_ui.draw();
        num_in.draw();

        rl.endDrawing();

        // Upadte
        app.back_b.update();
        num_in.update();

        if (a_update_timer.read() >= 100_000_000) a_ui.update(&a_handle);

        if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
            if (!finished) board_ui.update_click(&board);
            if (app.back_b.isHovered) return main.Scene.Menu;
        }

        if (board.isSelected()) {
            var res = board.doMove();
            if (res != Board.MoveResult.ok) {
                state.text = switch (res) {
                    .draw => "Draw!",
                    .win_true => "Red Won!",
                    .win_false => "Green Won!",
                    else => unreachable,
                };
                finished = true;
                a_handle.mutex.lock();
                a_handle.reload = true;
                a_handle.state = algo.State.wait;
                a_handle.mutex.unlock();
            } else {
                state.text = if (board.next_sign == 0) "Green's turn!" else "Red's turn!";
                a_handle.mutex.lock();
                a_handle.reload = true;
                a_handle.state = algo.State.run;
                a_handle.board = algo.Board.fromGBoard(board);
                a_handle.mutex.unlock();
            }
        }
    }
    return main.Scene.Quit;
}

const AlgoUi = struct {
    pos: rl.Vector2,
    font: rl.Font,
    font_size: f32,
    tint: rl.Color,

    state: algo.State,
    max_depth: u8,
    nodes: u64,
    moves: [42]algo.Move,
    moves_len: u8,
    scores: [42]i8,
    scores_len: u8,

    fn init(x: f32, y: f32, font: rl.Font, font_size: f32, tint: rl.Color, handle: *algo.Handle) AlgoUi {
        var a_state: AlgoUi = undefined;
        a_state.pos = rl.Vector2.init(x, y);
        a_state.font = font;
        a_state.font_size = font_size;
        a_state.tint = tint;
        a_state.update(handle);
        return a_state;
    }

    fn update(self: *AlgoUi, handle: *algo.Handle) void {
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

    fn draw(self: AlgoUi) void {
        var column_size = self.font_size + 4;
        var column_pos = self.pos;
        var buf: [16]u8 = undefined;
        var state_s = switch (self.state) {
            algo.State.quit => "quit",
            algo.State.wait => "wait",
            algo.State.run => "run",
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
                self.drawBuf(&buf, "Score: {}", .{self.scores[i]}, column_pos);
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

pub const BoardUi = struct {
    pos_x: i32,
    pos_y: i32,

    pub fn init(x: i32, y: i32) BoardUi {
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
        var start_x = if (board.next_sign == 0) self.pos_x - 250 else self.pos_x + 650;

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
