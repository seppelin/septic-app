mod gob;

use crate::gob::*;
use freya::prelude::*;
use gobblers::GameBoard;

fn main() {
    launch_cfg(
        app,
        LaunchConfig::<()>::builder()
            .with_title("septic")
            .with_width(1400.0)
            .with_height(900.0)
            .with_background("rgb(48, 48, 48)")
            .build(),
    );
}

fn app() -> Element {
    let mut is_algo = use_signal(|| false);
    let mut board = use_signal(|| GameBoard::new(true));

    rsx!(ThemeProvider{
        theme: DARK_THEME,
        rect {
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
        }
    })
}
