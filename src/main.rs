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

struct MacGrid {
    grid_x: [[f32; WIDTH + 1]; HEIGHT],
    grid_y: [[f32; WIDTH]; HEIGHT + 1],
}

const WIDTH: usize = 32;
const HEIGHT: usize = 18;
#[macroquad::main(window_conf)]
async fn main() {
    loop {
        // The velocities are stored in a staggered (MAC) grid, which means that the velocity values are stored on cell boundaries and not on cell centers.
        // This means that there are (width + 1) * height horizontal components and width * (height + 1) vertical components.
        let vel: MacGrid;

        // The pressures and divergences to correct are stored in a standard grid since it's more appropriate in this case
        let divergence: [[f32; WIDTH]; HEIGHT];
        let pressure: [[f32; WIDTH]; HEIGHT];
        clear_background(RED);
        draw_text("Initial project setup", 10.0, 500.0, 48.0, BLACK);
        next_frame().await;
    }
}
