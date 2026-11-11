use ::rand as random;
use macroquad::prelude::*;
use random::random;

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
    grid_x: [[f32; WIDTH + 1]; HEIGHT],
    grid_y: [[f32; WIDTH]; HEIGHT + 1],
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
            let left = self.grid_x[0][x.floor() as usize];
            let right = self.grid_x[0][x.floor() as usize + 1];
            left * x.fract() + right * (1.0 - x.fract())
        } else if y > FHEIGHT - 1.0 {
            // 2 points
            let left = self.grid_x[HEIGHT - 1][x.floor() as usize];
            let right = self.grid_x[HEIGHT - 1][x.floor() as usize + 1];
            left * x.fract() + right * (1.0 - x.fract())
        } else {
            let top_left = self.grid_x[y.floor() as usize][x.floor() as usize];
            let top_right = self.grid_x[y.floor() as usize][x.floor() as usize + 1];
            let btm_left = self.grid_x[y.floor() as usize + 1][x.floor() as usize];
            let btm_right = self.grid_x[y.floor() as usize + 1][x.floor() as usize + 1];

            let top = top_left * x.fract() + top_right * (1.0 - x.fract());
            let btm = btm_left * x.fract() + btm_right * (1.0 - x.fract());

            top * y.fract() + btm * (1.0 - y.fract())
        }
    }

    // Get y component
    fn bilinear_y(&self, x: f32, y: f32) -> f32 {
        let x = y - 0.5;
        if x < 0.0 {
            // 2 points
            let top = self.grid_y[y.floor() as usize][0];
            let btm = self.grid_y[y.floor() as usize + 1][0];
            top * y.fract() + btm * (1.0 - y.fract())
        } else if x > FWIDTH - 1.0 {
            // 2 points
            let top = self.grid_y[y.floor() as usize][WIDTH - 1];
            let btm = self.grid_y[y.floor() as usize + 1][WIDTH - 1];
            top * y.fract() + btm * (1.0 - y.fract())
        } else {
            let top_left = self.grid_y[y.floor() as usize][x.floor() as usize];
            let top_right = self.grid_y[y.floor() as usize][x.floor() as usize + 1];
            let btm_left = self.grid_y[y.floor() as usize + 1][x.floor() as usize];
            let btm_right = self.grid_y[y.floor() as usize + 1][x.floor() as usize + 1];

            let top = top_left * x.fract() + top_right * (1.0 - x.fract());
            let btm = btm_left * x.fract() + btm_right * (1.0 - x.fract());

            top * y.fract() + btm * (1.0 - y.fract())
        }
    }
    fn random() -> Self {
        Self {
            grid_x: random(),
            grid_y: random(),
        }
    }
}

impl Default for MacGrid {
    fn default() -> Self {
        Self {
            grid_x: [[0.0; WIDTH + 1]; HEIGHT],
            grid_y: [[0.0; WIDTH]; HEIGHT + 1],
        }
    }
}

#[derive(Default)]
struct Grid {
    grid: [[f32; WIDTH]; HEIGHT],
}

impl Grid {
    fn draw(&self) {
        for (y, row) in self.grid.iter().enumerate() {
            for (x, cell) in row.iter().enumerate() {
                let color = if *cell > 0.0 { BLUE } else { RED }.with_alpha(cell.abs() * 0.5);
                draw_rectangle(x as f32 * 50.0, y as f32 * 50.0, 50.0, 50.0, color);
            }
        }
    }
}

fn calculate_divergence(divergence: &mut Grid, velocities: &MacGrid) {
    for (y, row) in divergence.grid.iter_mut().enumerate() {
        for (x, cell) in row.iter_mut().enumerate() {
            *cell = velocities.grid_x[y][x + 1] + velocities.grid_y[y + 1][x]
                - velocities.grid_x[y][x]
                - velocities.grid_y[y][x];
        }
    }
}

fn calculate_pressure(pressure: &mut Grid, divergence: &Grid) {
    for y in 0..HEIGHT {
        for x in 0..WIDTH {
            let mut neighbours = 0;
            let top = if y != 0 {
                neighbours += 1;
                pressure.grid[y - 1][x]
            } else {
                0.0
            };

            let btm = if y != HEIGHT - 1 {
                neighbours += 1;
                pressure.grid[y + 1][x]
            } else {
                0.0
            };
            let left = if x != 0 {
                neighbours += 1;
                pressure.grid[y][x - 1]
            } else {
                0.0
            };
            let right = if x != WIDTH - 1 {
                neighbours += 1;
                pressure.grid[y][x + 1]
            } else {
                0.0
            };
            pressure.grid[y][x] =
                (top + btm + right + left) / neighbours as f32 - divergence.grid[y][x];
        }
    }
}

#[macroquad::main(window_conf)]
async fn main() {
    // The velocities are stored in a staggered (MAC) grid, which means that the velocity values are stored on cell boundaries and not on cell centers.
    // This means that there are (width + 1) * height horizontal components and width * (height + 1) vertical components.
    let vel: MacGrid = MacGrid::random();

    // The pressures and divergences to correct are stored in a standard grid since it's more appropriate in this case
    let mut divergence: Grid = Default::default();
    let mut pressure: Grid = Default::default();
    loop {
        clear_background(WHITE);
        calculate_divergence(&mut divergence, &vel);
        for _ in 0..50 {
            calculate_pressure(&mut pressure, &divergence);
        }
        pressure.draw();
        next_frame().await;
    }
}
