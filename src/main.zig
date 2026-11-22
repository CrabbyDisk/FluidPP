const std = @import("std");
const rl = @import("raylib");

const WIDTH = 96;
const HEIGHT = 54;

const SCALE: f32 = 20.0;
const DT: f32 = 1.0 / 75.0;

const vecLen = std.simd.suggestVectorLength(f32).?;
const vec = @Vector(vecLen, f32);
const GridSimd = [HEIGHT][@divExact(WIDTH, vecLen)]vec;
const Grid = [HEIGHT][WIDTH]f32;

fn calcDiv(div: *Grid, vel: MacGrid) void {
    for (div, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            const left = vel.gridX[y][x];
            const right = vel.gridX[y][x + 1];
            const top = vel.gridY[y][x];
            const btm = vel.gridY[y + 1][x];
            cell.* = right - left + btm - top;
        }
    }
}

fn calcPressure(pressure: *Grid, divergence: *const Grid) void {
    const old = pressure.*;
    for (pressure, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            const top = if (y == 0) old[y][x] else old[y - 1][x];
            const btm = if (y == HEIGHT - 1) old[y][x] else old[y + 1][x];
            const left = if (x == 0) old[y][x] else old[y][x - 1];
            const right = if (x == WIDTH - 1) old[y][x] else old[y][x + 1];
            cell.* = (top + btm + right + left - divergence[y][x]) / 4.0;
        }
    }
}

fn calcPressureSimd(pressure: *GridSimd, divergence: *const GridSimd) void {
    const old = pressure.*;
    for (pressure, 0..) |*row, y| {
        for (row, 0..) |*chunk, xChunk| {
            const top = if (y == 0) old[y][xChunk] else old[y - 1][xChunk];
            const btm = if (y == HEIGHT - 1) old[y][xChunk] else old[y + 1][xChunk];

            // const left = if (x == 0) old[y][x] else old[y][x - 1];
            const prevLast = if (xChunk == 0) old[y][xChunk][0] else old[y][xChunk - 1][vecLen - 1];
            const left = std.simd.shiftElementsRight(old[y][xChunk], 1, prevLast);

            // const right = if (x == WIDTH - 1) old[y][x] else old[y][x + 1];
            const nextFirst = if (xChunk == WIDTH / vecLen - 1) old[y][xChunk][vecLen - 1] else old[y][xChunk + 1][0];
            const right = std.simd.shiftElementsLeft(old[y][xChunk], 1, nextFirst);
            chunk.* = (top + btm + right + left - divergence[y][xChunk]) / @as(vec, @splat(4.0));
        }
    }
}

const MacGrid = struct {
    gridX: [HEIGHT][WIDTH + 1]f32,
    gridY: [HEIGHT + 1][WIDTH]f32,

    fn zeroes() MacGrid {
        return .{
            .gridX = @splat(@splat(0.0)),
            .gridY = @splat(@splat(0.0)),
        };
    }

    fn getCellPtrs(self: *MacGrid, x: f32, y: f32) struct { *f32, *f32 } {
        return .{
            &self.gridX[@round(y - 0.5)][@round(x)],
            &self.gridY[@round(y)][@round(x - 0.5)],
        };
    }

    fn bilinearX(self: MacGrid, x: f32, yOffset: f32) f32 {
        const y = yOffset - 0.5;
        if (y < 0.0) {
            const left = self.gridX[0][@trunc(x)];
            const right = self.gridX[0][@min(@as(usize, @trunc(x)) + 1, WIDTH)];
            return right * (x - @floor(x)) + left * (1.0 - x + @floor(x));
        } else if (y >= HEIGHT - 1.0) {
            const left = self.gridX[HEIGHT - 1][@trunc(x)];
            const right = self.gridX[HEIGHT - 1][@min(@as(usize, @trunc(x)) + 1, WIDTH)];
            return right * (x - @floor(x)) + left * (1.0 - x + @floor(x));
        } else {
            const topLeft = self.gridX[@trunc(y)][@trunc(x)];
            const topRight = self.gridX[@trunc(y)][@min(@as(usize, @trunc(x)) + 1, WIDTH)];
            const btmLeft = self.gridX[@as(usize, @trunc(y)) + 1][@trunc(x)];
            const btmRight = self.gridX[@as(usize, @trunc(y)) + 1][@min(@as(usize, @trunc(x)) + 1, WIDTH)];

            const top = topRight * (x - @floor(x)) + topLeft * (1.0 - x + @floor(x));
            const btm = btmRight * (x - @floor(x)) + btmLeft * (1.0 - x + @floor(x));
            return btm * (y - @floor(y)) + top * (1.0 - y + @floor(y));
        }
    }

    fn bilinearY(self: MacGrid, xOffset: f32, y: f32) f32 {
        const x = xOffset - 0.5;
        if (x < 0.0) {
            const top = self.gridY[@trunc(y)][0];
            const btm = self.gridY[@min(@as(usize, @trunc(y)) + 1, HEIGHT)][0];
            return btm * (y - @floor(y)) + top * (1.0 - y + @floor(y));
        }
        if (x >= WIDTH - 1.0) {
            const top = self.gridY[@trunc(y)][WIDTH - 1];
            const btm = self.gridY[@min(@as(usize, @trunc(y)) + 1, HEIGHT)][WIDTH - 1];
            return btm * (y - @floor(y)) + top * (1.0 - y + @floor(y));
        } else {
            const topLeft = self.gridY[@trunc(y)][@trunc(x)];
            const topRight = self.gridY[@trunc(y)][@as(usize, @trunc(x)) + 1];
            const btmLeft = self.gridY[@min(@as(usize, @trunc(y)) + 1, HEIGHT)][@trunc(x)];
            const btmRight = self.gridY[@min(@as(usize, @trunc(y)) + 1, HEIGHT)][@as(usize, @trunc(x)) + 1];

            const top = topRight * (x - @floor(x)) + topLeft * (1.0 - x + @floor(x));
            const btm = btmRight * (x - @floor(x)) + btmLeft * (1.0 - x + @floor(x));
            return btm * (y - @floor(y)) + top * (1.0 - y + @floor(y));
        }
    }

    fn drawArrows(self: MacGrid) void {
        for (0..HEIGHT) |y| {
            for (0..WIDTH) |x| {
                const xComp = 0.5 * (self.gridX[y][x] + self.gridX[y][x + 1]) * SCALE / 10.0;
                const yComp = 0.5 * (self.gridY[y][x] + self.gridY[y + 1][x]) * SCALE / 10.0;
                const xPos: f32 = (@as(f32, @floatFromInt(x)) + 0.5) * SCALE;
                const yPos: f32 = (@as(f32, @floatFromInt(y)) + 0.5) * SCALE;

                const angle = std.math.atan2(yComp, xComp);

                const tip = rl.Vector2{
                    .x = xPos + xComp,
                    .y = yPos + yComp,
                };

                rl.drawLineV(.{ .x = xPos, .y = yPos }, .{ .x = xPos + xComp, .y = yPos + yComp }, .black);
                rl.drawTriangle(
                    tip.add((rl.Vector2{ .x = 0.0, .y = -5.0 }).rotate(angle)),
                    tip.add((rl.Vector2{ .x = 0.0, .y = 5.0 }).rotate(angle)),
                    tip.add((rl.Vector2{ .x = 8.66, .y = 0.0 }).rotate(angle)),
                    .black,
                );
            }
        }
    }
};

fn project(vel: *MacGrid, pressure: Grid) void {
    for (&vel.gridX, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            if (x == 0 or x == WIDTH) {
                cell.* = 0.0;
            } else {
                const left = pressure[y][x - 1];
                const right = pressure[y][x];
                cell.* -= right - left;
            }
        }
    }
    for (&vel.gridY, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            if (y == 0 or y == HEIGHT) {
                cell.* = 0.0;
            } else {
                const top = pressure[y - 1][x];
                const btm = pressure[y][x];
                cell.* -= btm - top;
            }
        }
    }
}

fn advect(vel: *MacGrid) void {
    const old = vel.*;
    for (&vel.gridX, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            const posX: f32 = @floatFromInt(x);
            const posY: f32 = @as(f32, @floatFromInt(y)) + 0.5;
            const dX = old.gridX[y][x];
            const dY = old.bilinearY(posX, posY);
            const backX = posX - dX * DT;
            const backY = posY - dY * DT;
            cell.* = vel.bilinearX(backX, backY);
        }
    }
    for (&vel.gridY, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            const posX: f32 = @as(f32, @floatFromInt(x)) + 0.5;
            const posY: f32 = @as(f32, @floatFromInt(y));
            const dX = old.bilinearX(posX, posY);
            const dY = old.gridY[y][x];
            const backX = posX - dX * DT;
            const backY = posY - dY * DT;
            cell.* = vel.bilinearY(backX, backY);
        }
    }
}

fn advect2(vel: *MacGrid) void {
    const old = vel.*;
    for (&vel.gridX, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            const posX: f32 = @floatFromInt(x);
            const posY: f32 = @as(f32, @floatFromInt(y)) + 0.5;
            const dX = old.gridX[y][x];

            const dY = blk: {
                if (x == 0) {
                    const top = old.gridY[y][0];
                    const btm = old.gridY[y + 1][0];
                    break :blk (btm + top) * 0.5;
                } else if (x == WIDTH - 1) {
                    const top = old.gridY[y][WIDTH - 1];
                    const btm = old.gridY[y + 1][WIDTH - 1];
                    break :blk (btm + top) * 0.5;
                } else {
                    const topRight = old.gridY[y][x];
                    const topLeft = old.gridY[y][x - 1];
                    const btmRight = old.gridY[y + 1][x];
                    const btmLeft = old.gridY[y + 1][x - 1];
                    break :blk (topLeft + topRight + btmLeft + btmRight) * 0.25;
                }
            };

            const backX = posX - dX * DT;
            const backY = posY - dY * DT;
            cell.* = vel.bilinearX(backX, backY);
        }
    }
    for (&vel.gridY, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            const posX: f32 = @as(f32, @floatFromInt(x)) + 0.5;
            const posY: f32 = @as(f32, @floatFromInt(y));

            const dX = blk: {
                if (y == 0) {
                    const left = old.gridX[0][x];
                    const right = old.gridX[0][x + 1];
                    break :blk (left + right) * 0.5;
                } else if (y == HEIGHT - 1) {
                    const left = old.gridX[HEIGHT - 1][x];
                    const right = old.gridX[HEIGHT - 1][x + 1];
                    break :blk (left + right) * 0.5;
                } else {
                    const btmLeft = old.gridX[y][x];
                    const topLeft = old.gridX[y - 1][x];
                    const btmRight = old.gridX[y][x + 1];
                    const topRight = old.gridX[y - 1][x + 1];
                    break :blk (topLeft + topRight + btmLeft + btmRight) * 0.25;
                }
            };

            const dY = old.gridY[y][x];
            const backX = posX - dX * DT;
            const backY = posY - dY * DT;
            cell.* = vel.bilinearY(backX, backY);
        }
    }
}
pub fn main(init: std.process.Init) !void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;

    rl.setConfigFlags(.{ .vsync_hint = true, .fullscreen_mode = true });
    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    //--------------------------------------------------------------------------------------

    var vel: MacGrid = .zeroes();
    var div: Grid align(@alignOf(vec)) = @splat(@splat(0.0));
    var pressure: Grid align(@alignOf(vec)) = @splat(@splat(0.0));
    const clock = std.Io.Clock.awake;

    var useSimd = true;
    var useNewAdvect = true;

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key

        const pos = rl.getMousePosition();
        if (rl.isMouseButtonDown(.left)) {
            const delta = rl.getMouseDelta();
            const cellX, const cellY = vel.getCellPtrs(pos.x / SCALE, pos.y / SCALE);
            cellX.* += delta.x / SCALE * 10.0;
            cellY.* += delta.y / SCALE * 10.0;
        }
        // Update
        //----------------------------------------------------------------------------------

        const updateStart = clock.now(init.io);
        calcDiv(&div, vel);
        if (useSimd) {
            for (0..400) |_| {
                calcPressureSimd(@ptrCast(&pressure), @ptrCast(&div));
            }
        } else {
            for (0..400) |_| {
                calcPressure(&pressure, &div);
            }
        }
        if (rl.isKeyPressed(.space)) {
            useSimd = !useSimd;
        }
        if (rl.isKeyPressed(.a)) {
            useNewAdvect = !useNewAdvect;
        }
        project(&vel, pressure);
        if (useNewAdvect) {
            advect2(&vel);
        } else {
            advect(&vel);
        }
        const updateTime = updateStart.untilNow(init.io, clock);
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        const drawStart = clock.now(init.io);

        rl.clearBackground(.white);
        vel.drawArrows();

        const drawTime = drawStart.untilNow(init.io, clock);

        rl.drawFPS(0, 0);
        {
            var buf: [16]u8 = std.mem.zeroes([16]u8);
            var writer = std.Io.Writer.fixed(&buf);
            try updateTime.format(&writer);
            rl.drawText(@ptrCast(&buf), 0, 20, 20, .red);
        }
        {
            var buf: [16]u8 = std.mem.zeroes([16]u8);
            var writer = std.Io.Writer.fixed(&buf);
            try drawTime.format(&writer);
            rl.drawText(@ptrCast(&buf), 0, 40, 20, .red);
        }
        //----------------------------------------------------------------------------------
    }
}
