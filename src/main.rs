use macroquad::prelude::*;

fn window_conf() -> Conf {
    use macroquad::miniquad;

    Conf {
        window_title: "window".to_owned(),
        fullscreen: false,
        platform: miniquad::conf::Platform {
            linux_backend: miniquad::conf::LinuxBackend::WaylandOnly,
            ..Default::default()
        },
        ..Default::default()
    }
}

#[macroquad::main(window_conf)]
async fn main() {
    loop {
        clear_background(RED);
        draw_text("Initial project setup", 10.0, 500.0, 48.0, BLACK);
        next_frame().await;
    }
}
