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

const WIDTH: usize = 32;
const FWIDTH: f32 = WIDTH as f32;
const HEIGHT: usize = 18;
const FHEIGHT: f32 = HEIGHT as f32;

struct MacGrid {
    grid_x: [[f32; HEIGHT + 1]; WIDTH],
    grid_y: [[f32; HEIGHT]; WIDTH + 1],
}

impl MacGrid {
    pub fn bilinear(self, x: f32, y: f32) -> (f32, f32) {
        if x < 0.0 || y < 0.0 || x > FWIDTH || y > FHEIGHT {
            (0.0, 0.0)
        } else {
            (self.bilinear_x(x, y), self.bilinear_y(x, y))
        }
    }

    // Get x component
    fn bilinear_x(&self, x: f32, y: f32) -> f32 {
        let y = y - 0.5;
        if y < 0.0 {
            // 2 points
            let left = self.grid_x[x.floor() as usize][0];
            let right = self.grid_x[x.floor() as usize + 1][0];
            left * x.fract() + right * (1.0 - x.fract())
        } else if y > FHEIGHT - 1.0 {
            // 2 points
            let left = self.grid_x[x.floor() as usize][HEIGHT - 1];
            let right = self.grid_x[x.floor() as usize + 1][HEIGHT - 1];
            left * x.fract() + right * (1.0 - x.fract())
        } else {
            let top_left = self.grid_x[x.floor() as usize][y.floor() as usize];
            let top_right = self.grid_x[x.floor() as usize + 1][y.floor() as usize];
            let btm_left = self.grid_x[x.floor() as usize][y.floor() as usize + 1];
            let btm_right = self.grid_x[x.floor() as usize + 1][y.floor() as usize + 1];

            let top = top_left * x.fract() + top_right * (1.0 - x.fract());
            let btm = btm_left * x.fract() + btm_right * (1.0 - x.fract());

            top * y.fract() + btm * (1.0 - y.fract())
        }
    }

    fn bilinear_y(&self, x: f32, y: f32) -> f32 {
        let x = y - 0.5;
        if x < 0.0 {
            // 2 points
            let top = self.grid_y[0][y.floor() as usize];
            let btm = self.grid_y[0][y.floor() as usize + 1];
            top * y.fract() + btm * (1.0 - y.fract())
        } else if x > FWIDTH - 1.0 {
            // 2 points
            let top = self.grid_y[WIDTH][y.floor() as usize];
            let btm = self.grid_y[WIDTH][y.floor() as usize + 1];
            top * y.fract() + btm * (1.0 - y.fract())
        } else {
            let top_left = self.grid_y[x.floor() as usize][y.floor() as usize];
            let top_right = self.grid_y[x.floor() as usize + 1][y.floor() as usize];
            let btm_left = self.grid_y[x.floor() as usize][y.floor() as usize + 1];
            let btm_right = self.grid_y[x.floor() as usize + 1][y.floor() as usize + 1];

            let top = top_left * x.fract() + top_right * (1.0 - x.fract());
            let btm = btm_left * x.fract() + btm_right * (1.0 - x.fract());

            top * y.fract() + btm * (1.0 - y.fract())
        }
    }
}

#[macroquad::main(window_conf)]
async fn main() {
    loop {
        // The velocities are stored in a staggered (MAC) grid, which means that the velocity values are stored on cell boundaries and not on cell centers.
        // This means that there are (width + 1) * height horizontal components and width * (height + 1) vertical components.
        let vel: MacGrid;

        // The pressures and divergences to correct are stored in a standard grid since it's more appropriate in this case
        let divergence: [[f32; WIDTH]; HEIGHT];
        let pressure: [[f32; HEIGHT]; WIDTH];
        clear_background(RED);
        draw_text("Initial project setup", 10.0, 500.0, 48.0, BLACK);
        next_frame().await;
    }
}
