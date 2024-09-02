#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

mod gob;
mod menu;

use freya::prelude::*;
use menu::App;

fn main() {
    launch_cfg(
        app,
        LaunchConfig::<()>::new()
            .with_title("septic")
            .with_size(1400.0, 900.0)
            //.with_plugin(PerformanceOverlayPlugin::default())
    );
}

fn app() -> Element {
    rsx!(ThemeProvider{
        theme: DARK_THEME,
        App{},
    })
}
