use std::cmp::Ordering;

use freya::prelude::*;
use gobblers::*;
use skia_safe::{Canvas, Color, Paint};

fn get_board_coord(unit: f32, pos: i32) -> (f32, f32) {
    let (w, h) = ((pos % 3) as f32, (pos / 3) as f32);
    return (unit * 1.5 + w * unit * 1.125, h * unit * 1.125);
}

fn get_new_coord(unit: f32, player: i32, size: i32) -> (f32, f32) {
    let x = {
        if player == 0 {
            0.0
        } else {
            unit * 5.25
        }
    };
    return (x, (size as f32) * unit * 1.125);
}

fn render_piece(
    canvas: &Canvas,
    unit: f32,
    coord: (f32, f32),
    player: i32,
    size: i32,
    hovered: bool,
) {
    let sizes = [0.35, 0.60, 0.85];
    let rad = sizes[size as usize] * unit / 2.0;
    let colors = [Color::GREEN, Color::RED];
    let mut paint = Paint::default();
    paint.set_anti_alias(true);
    paint.set_color(colors[player as usize]);
    canvas.draw_circle((coord.0 + unit / 2.0, coord.1 + unit / 2.0), rad, &paint);
    paint.set_color(Color::BLACK);
    paint.set_style(skia_safe::PaintStyle::Stroke);
    paint.set_stroke_width(unit / 72.0);
    canvas.draw_circle((coord.0 + unit / 2.0, coord.1 + unit / 2.0), rad, &paint);
    if hovered {
        paint.set_color(Color::YELLOW);
        paint.set_alpha(128);
        paint.set_stroke_width(unit / 48.0);
        canvas.draw_circle((coord.0 + unit / 2.0, coord.1 + unit / 2.0), rad, &paint);
    }
}

fn render_board(canvas: &Canvas, unit: f32, boarder: &Paint, b: &GameBoard) {
    for pos in 0..9 {
        let (x, y) = get_board_coord(unit, pos);
        canvas.draw_round_rect(
            skia_safe::Rect::new(x, y, x + unit, y + unit),
            unit / 4.0,
            unit / 4.0,
            boarder,
        );
        if let Some((p, s)) = b.get_top(pos) {
            render_piece(
                canvas,
                unit,
                (x, y),
                p,
                s,
                b.is_selected_board(pos) && b.player() == p,
            );
        }
    }
}

fn render_new(canvas: &Canvas, unit: f32, player: i32, boarder: &Paint, b: &GameBoard) {
    let start = get_new_coord(unit, player, 0);
    canvas.draw_round_rect(
        skia_safe::Rect::new(start.0, start.1, start.0 + unit, start.1 + unit * 3.25),
        unit / 4.0,
        unit / 4.0,
        boarder,
    );
    for size in 0..3 {
        let mut coord = get_new_coord(unit, player, size);
        if b.get_left(player, size) > 1 {
            render_piece(canvas, unit, coord, player, size, false);
            coord.1 -= unit / 16.0;
        }
        if b.get_left(player, size) > 0 {
            render_piece(
                canvas,
                unit,
                coord,
                player,
                size,
                b.is_selected_new(size) && b.player() == player,
            );
        }
    }
}

#[component]
pub fn Gob() -> Element {
    let mut is_algo = use_signal(|| false);
    let mut board = use_signal(|| GameBoard::new(true));

    rsx!(rect {
        width: "100%",
        height: "100%",
        rect {
            padding: "10",
            width: "fill",
            main_align: "end",
            cross_align: "end",
            direction: "horizontal",
            Button {
                onclick: move |_| {
                    let new = !*is_algo.read();
                    is_algo.replace(new);
                },
                label {
                    "Toggle Algo"
                }
            }
            Button {
                onclick: move |_| {
                    board.replace(GameBoard::new(true));
                },
                label {
                    "Reset"
                }
            }
            Button {
                onclick: move |_| {
                    board.write().undo_move();
                },
                label {
                    "Undo"
                }
            }
        }
        rect {
            direction: "horizontal",
            width: "fill",
            height: "fill",
            main_align: "end",
            rect {
                width: if *is_algo.read() {
                     "calc(100% - 250)"
                } else {
                    "100%"
                },
                height: "fill",
                GobBoard{ board }
            }
            if *is_algo.read() {
                GobAlgo{ board }
            }
        }
    })
}

#[component]
pub fn GobAlgo(board: Signal<GameBoard>) -> Element {
    use search::*;
    let mut search = use_hook_with_cleanup(|| Search::new(), |s| s.flush());
    let mut last_board = use_signal(|| Board {
        layers: [0; 6],
        pieces: [0; 6],
        player: 4,
    });
    let mut evals = use_signal(|| Vec::new());
    if *last_board.read() != *board.read().get_board() {
        last_board.replace(*board.read().get_board());
        if board.read().get_state() == State::InGame {
            evals.replace(
                board
                    .read()
                    .get_moves()
                    .iter()
                    .map(|m| {
                        let mut b = board.read().clone();
                        b.do_move(*m);
                        let mut eval = search.evaluate(&b, 9);
                        eval.depth += 1;
                        if eval.kind == EvalKind::Win {
                            eval.kind = EvalKind::Loss;
                        } else if eval.kind == EvalKind::Loss {
                            eval.kind = EvalKind::Win;
                        }
                        (*m, eval)
                    })
                    .collect(),
            );
        } else {
            evals.write().clear();
        }
    }

    let mut sorted_evals = evals.read().clone();
    sorted_evals.sort_by(|a, b| {
        let get_score = |e: Evaluation| {
            if e.kind == EvalKind::Win {
                100 - e.depth as i32
            } else if e.kind == EvalKind::Loss {
                -100 + e.depth as i32
            } else if e.kind == EvalKind::TooFar {
                -50 + e.depth as i32
            } else {
                0 - e.depth as i32
            }
        };
        let mut order = get_score(b.1).cmp(&get_score(a.1));
        if order == Ordering::Equal {
            order = b.1.nodes.cmp(&a.1.nodes);
        }
        return order;
    });

    rsx!(rect {
        padding: "0 15",
        width: "250",
        height: "fill",
        cross_align: "center",
        label {
            color: "white",
            font_weight: "bold",
            font_size: "36",
            "Algorithm"
        }
        ScrollView{
            for (m, e) in sorted_evals.iter() {{
                let move_name = if m.is_new {
                    format!("New: s{} t{}", m.size, m.to)
                } else {
                    format!("Board: s{} f{} t{}", m.size, m.from, m.to)
                };
                let color = if e.kind == EvalKind::Win {
                    "yellow"
                } else if e.kind == EvalKind::Loss {
                    "orange"
                } else if e.kind == EvalKind::Draw {
                    "gray"
                } else {
                    "white"
                };
                let m_clone = *m;
                rsx!(rect{
                    padding: "2",
                    border: "1 solid gray",
                    margin: "2 0",
                    corner_radius: "5",
                    font_size: "22",
                    onclick: move |_| {
                        board.clone().write().do_move(m_clone);
                    },
                    label {
                        color,
                        "{move_name}"
                    }
                    label {
                        color,
                        "{e.kind:?}: {e.depth}, {e.time:.2}, {e.nodes/1_000}k"
                    }
                })
            }}
        }
    })
}

#[component]
pub fn GobBoard(board: Signal<GameBoard>) -> Element {
    let pos = use_signal_sync(|| (0 as f32, (0.0, 0.0)));

    let canvas = use_canvas(move || {
        let b = board();
        Box::new(move |ctx| {
            let (max_x, max_y) = ctx.area.size.to_tuple();
            let unit = std::cmp::min((max_x / 6.25) as i32, (max_y / 3.25) as i32) as f32;

            let trans_x = ctx.area.min_x() + (max_x - unit * 6.25) / 2.0;
            let trans_y = ctx.area.min_y() + (max_y - unit * 3.25) / 2.0;

            pos.clone().replace((unit, (trans_x, trans_y)));

            // Translate to board start
            ctx.canvas.translate((trans_x, trans_y));

            let mut border = Paint::default();
            border.set_color(Color::from_rgb(150, 110, 150));
            border.set_anti_alias(true);
            border.set_style(skia_safe::PaintStyle::Stroke);
            border.set_stroke_width(unit / 32.0);

            render_new(ctx.canvas, unit, 0, &border, &b);
            render_new(ctx.canvas, unit, 1, &border, &b);
            render_board(ctx.canvas, unit, &border, &b);
        })
    });

    let onclick = move |e: Event<MouseData>| {
        let player = board.read().player();
        let (unit, (start_x, start_y)) = *pos.clone().read();
        let mx = e.screen_coordinates.x as f32;
        let my = e.screen_coordinates.y as f32;

        let is_click = |x: f32, y: f32| {
            let is_x = (start_x + x <= mx) && (start_x + x + unit >= mx);
            let is_y = (start_y + y <= my) && (start_y + y + unit >= my);
            return is_x && is_y;
        };

        let mut b = board.write();
        for size in 0..3 {
            let (x, y) = get_new_coord(unit, player, size);
            if is_click(x, y) {
                b.select_new(player, size);
                return;
            }
        }
        for pos in 0..9 {
            let (x, y) = get_board_coord(unit, pos);
            if is_click(x, y) {
                b.select_board(pos);
                return;
            }
        }
        b.remove_select();
    };

    rsx!(
        rect {
            width: "fill",
            height: "fill",
            padding: "10",
            onclick,
            Canvas {
                canvas,
                theme: theme_with!(CanvasTheme {
                    background: "transparent".into(),
                    width: "fill".into(),
                    height: "fill".into(),
                }),
            }
        }
    )
}
