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

const DT: f32 = 0.16;

#[derive(Copy, Clone)]
struct MacGrid {
    grid_x: [[f32; WIDTH + 1]; HEIGHT],
    grid_y: [[f32; WIDTH]; HEIGHT + 1],
}

impl MacGrid {
    // Get x component
    fn bilinear_x(&self, x: f32, y: f32) -> f32 {
        let y = y - 0.5;
        if y < 0.0 {
            // 2 points
            let left = self.grid_x[0][x.floor() as usize];
            let right = self.grid_x[0][(x.floor() as usize + 1).min(WIDTH)];
            right * x.fract() + left * (1.0 - x.fract())
        } else if y >= FHEIGHT - 1.0 {
            // 2 points
            let left = self.grid_x[HEIGHT - 1][x.floor() as usize];
            let right = self.grid_x[HEIGHT - 1][(x.floor() as usize + 1).min(WIDTH)];
            right * x.fract() + left * (1.0 - x.fract())
        } else {
            let top_left = self.grid_x[y.floor() as usize][x.floor() as usize];
            let top_right = self.grid_x[y.floor() as usize][(x.floor() as usize + 1).min(WIDTH)];
            let btm_left = self.grid_x[y.floor() as usize + 1][x.floor() as usize];
            let btm_right =
                self.grid_x[y.floor() as usize + 1][(x.floor() as usize + 1).min(WIDTH)];

            let top = top_right * x.fract() + top_left * (1.0 - x.fract());
            let btm = btm_right * x.fract() + btm_left * (1.0 - x.fract());

            btm * y.fract() + top * (1.0 - y.fract())
        }
    }

    // Get y component
    fn bilinear_y(&self, x: f32, y: f32) -> f32 {
        let x = x - 0.5;
        if x < 0.0 {
            // 2 points
            let top = self.grid_y[y.floor() as usize][0];
            let btm = self.grid_y[(y.floor() as usize + 1).min(HEIGHT)][0];
            btm * y.fract() + top * (1.0 - y.fract())
        } else if x >= FWIDTH - 1.0 {
            // 2 points
            let top = self.grid_y[y.floor() as usize][WIDTH - 1];
            let btm = self.grid_y[(y.floor() as usize + 1).min(HEIGHT)][WIDTH - 1];
            btm * y.fract() + top * (1.0 - y.fract())
        } else {
            let top_left = self.grid_y[y.floor() as usize][x.floor() as usize];
            let top_right = self.grid_y[y.floor() as usize][x.floor() as usize + 1];
            let btm_left = self.grid_y[(y.floor() as usize + 1).min(HEIGHT)][x.floor() as usize];
            let btm_right =
                self.grid_y[(y.floor() as usize + 1).min(HEIGHT)][x.floor() as usize + 1];

            let top = top_right * x.fract() + top_left * (1.0 - x.fract());
            let btm = btm_right * x.fract() + btm_left * (1.0 - x.fract());

            btm * y.fract() + top * (1.0 - y.fract())
        }
    }

    fn draw(&self) {
        for (y, row) in self.grid_x.iter().enumerate() {
            for (x, cell) in row.iter().enumerate() {
                let x = x as f32 * 50.0;
                let y = y as f32 * 50.0 + 25.0;
                draw_line(
                    x,
                    y,
                    x + cell * 25.0,
                    y,
                    2.0,
                    if *cell > 0.0 { BLUE } else { RED },
                );
                draw_triangle(
                    Vec2 {
                        x: x + cell * 25.0,
                        y: y - 5.0,
                    },
                    Vec2 {
                        x: x + cell * 25.0,
                        y: y + 5.0,
                    },
                    Vec2 {
                        x: x + cell * 25.0 + 7.0 * cell.signum(),
                        y,
                    },
                    if *cell > 0.0 { BLUE } else { RED },
                );
            }
        }
        for (y, row) in self.grid_y.iter().enumerate() {
            for (x, cell) in row.iter().enumerate() {
                let x = x as f32 * 50.0 + 25.0;
                let y = y as f32 * 50.0;
                draw_line(
                    x,
                    y,
                    x,
                    y + cell * 25.0,
                    2.0,
                    if *cell > 0.0 { BLUE } else { RED },
                );
                draw_triangle(
                    Vec2 {
                        y: y + cell * 25.0,
                        x: x - 5.0,
                    },
                    Vec2 {
                        y: y + cell * 25.0,
                        x: x + 5.0,
                    },
                    Vec2 {
                        y: y + cell * 25.0 + 7.0 * cell.signum(),
                        x,
                    },
                    if *cell > 0.0 { BLUE } else { RED },
                )
            }
        }
    }

    fn get_cell_mut(&mut self, x: f32, y: f32) -> (&mut f32, &mut f32) {
        (
            &mut self.grid_x[(y - 0.5).round() as usize][x.round() as usize],
            &mut self.grid_y[y.round() as usize][(x - 0.5).round() as usize],
        )
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

#[derive(Clone, Copy)]
struct Grid {
    grid: [[f32; WIDTH]; HEIGHT],
}

impl Grid {
    fn draw(&self) {
        for (y, row) in self.grid.iter().enumerate() {
            for (x, cell) in row.iter().enumerate() {
                let color = if *cell > 0.0 { BLUE } else { RED }.with_alpha(cell.abs());
                draw_rectangle(x as f32 * 50.0, y as f32 * 50.0, 50.0, 50.0, color);
            }
        }
    }
}

impl Default for Grid {
    fn default() -> Self {
        Self {
            grid: [[0.0; WIDTH]; HEIGHT],
        }
    }
}

fn calculate_divergence(divergence: &mut Grid, velocities: &MacGrid) {
    for (y, row) in divergence.grid.iter_mut().enumerate() {
        for (x, cell) in row.iter_mut().enumerate() {
            let left = velocities.grid_x[y][x];
            let right = velocities.grid_x[y][x + 1];
            let top = velocities.grid_y[y][x];
            let btm = velocities.grid_y[y + 1][x];
            *cell = right - left + btm - top;
        }
    }
}

fn calculate_pressure(pressure: &mut Grid, divergence: &Grid) {
    let old = *pressure;
    for (y, row) in pressure.grid.iter_mut().enumerate() {
        for (x, cell) in row.iter_mut().enumerate() {
            let top = if y == 0 {
                old.grid[y][x]
            } else {
                old.grid[y - 1][x]
            };

            let btm = if y == HEIGHT - 1 {
                old.grid[y][x]
            } else {
                old.grid[y + 1][x]
            };
            let left = if x == 0 {
                old.grid[y][x]
            } else {
                old.grid[y][x - 1]
            };
            let right = if x == WIDTH - 1 {
                old.grid[y][x]
            } else {
                old.grid[y][x + 1]
            };
            *cell = (top + btm + right + left - divergence.grid[y][x]) / 4.0;
        }
    }
}

fn project(vel: &mut MacGrid, pressure: &Grid) {
    for (y, row) in vel.grid_x.iter_mut().enumerate() {
        for (x, cell) in row.iter_mut().enumerate() {
            if x == 0 || x == WIDTH {
                *cell = 0.0;
            } else {
                let left = pressure.grid[y][x - 1];
                let right = pressure.grid[y][x];
                *cell -= right - left;
            }
        }
    }
    for (y, row) in vel.grid_y.iter_mut().enumerate() {
        for (x, cell) in row.iter_mut().enumerate() {
            if y == 0 || y == HEIGHT {
                *cell = 0.0;
            } else {
                let top = pressure.grid[y - 1][x];
                let btm = pressure.grid[y][x];
                *cell -= btm - top;
            }
        }
    }
}

fn advect_velocity(vel: &mut MacGrid) {
    let old = *vel;
    for (y, row) in vel.grid_x.iter_mut().enumerate() {
        for (x, cell) in row.iter_mut().enumerate() {
            let pos_x = x as f32;
            let pos_y = y as f32 + 0.5;

            let dx = old.grid_x[y][x];
            let dy = old.bilinear_y(pos_x, pos_y);

            let back_x = pos_x - dx * DT;
            let back_y = pos_y - dy * DT;

            *cell = old.bilinear_x(back_x, back_y);
        }
    }
    for (y, row) in vel.grid_y.iter_mut().enumerate() {
        for (x, cell) in row.iter_mut().enumerate() {
            let pos_y = y as f32;
            let pos_x = x as f32 + 0.5;
            let dy = old.grid_y[y][x];
            let dx = old.bilinear_x(pos_x, pos_y);
            *cell = old.bilinear_y(pos_x - dx * 0.0005, pos_y - dy * 0.0005);
        }
    }
}

#[macroquad::main(window_conf)]
async fn main() {
    // The velocities are stored in a staggered (MAC) grid, which means that the velocity values are stored on cell boundaries and not on cell centers.
    // This means that there are (width + 1) * height horizontal components and width * (height + 1) vertical components.
    let mut vel: MacGrid = MacGrid::default();

    // The pressures and divergences to correct are stored in a standard grid since it's more appropriate in this case
    let mut divergence: Grid = Default::default();
    let mut pressure: Grid = Default::default();
    loop {
        if is_mouse_button_down(MouseButton::Left) {
            let (x, y) = mouse_position();
            let Vec2 { x: dx, y: dy } = mouse_delta_position();
            let (cell_x, cell_y) = vel.get_cell_mut(x / 50.0, y / 50.0);
            *cell_x -= dx * 10.0;
            *cell_y -= dy * 10.0;
        }
        clear_background(WHITE);
        // if is_key_pressed(KeyCode::Space) {
        advect_velocity(&mut vel);
        // }
        calculate_divergence(&mut divergence, &vel);
        // pressure = Default::default();
        for _ in 0..200 {
            calculate_pressure(&mut pressure, &divergence);
        }
        project(&mut vel, &pressure);
        pressure.draw();
        vel.draw();
        next_frame().await;
    }
}
