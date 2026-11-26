const std = @import("std");

const rl = @import("raylib");
const rg = @import("raygui");

const WIDTH = 64;
const HEIGHT = 36;

const SCALE: f32 = 20.0;
const DT: f32 = 1.0 / 75.0;

const vecLen = std.simd.suggestVectorLength(f32).?;
const vec = @Vector(vecLen, f32);
const GridSimd = [HEIGHT][@divExact(WIDTH, vecLen)]vec;
const Grid = [HEIGHT][WIDTH]f32;

const boolVec = @Vector(vecLen, bool);
const WallGrid = [HEIGHT]std.bit_set.Array(u8, WIDTH);
const WallGridSimd = [HEIGHT][@divExact(WIDTH, vecLen)]boolVec;

fn calcDiv(div: *Grid, vel: *const MacGrid) void {
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

fn calcPressure(pressure: *GridSimd, divergence: *const GridSimd, walls: *const WallGridSimd) void {
    const old = pressure.*;
    for (pressure, 0..) |*row, y| {
        for (row, 0..) |*chunk, x| {
            const topWall: boolVec = if (y == 0) @splat(true) else walls[y - 1][x];
            const topRow = if (y == 0) undefined else old[y - 1][x];
            const top = @select(f32, topWall, old[y][x], topRow);

            const btmWall: boolVec = if (y == HEIGHT - 1) @splat(true) else walls[y + 1][x];
            const btmRow = if (y == HEIGHT - 1) undefined else old[y + 1][x];
            const btm = @select(f32, btmWall, old[y][x], btmRow);

            const leftWall = if (x == 0)
                std.simd.shiftElementsRight(walls[y][x], 1, true)
            else
                std.simd.shiftElementsRight(walls[y][x], 1, walls[y][x - 1][vecLen - 1]);
            const prevLast = if (x == 0) old[y][x][0] else old[y][x - 1][vecLen - 1];
            const leftRow = std.simd.shiftElementsRight(old[y][x], 1, prevLast);
            const left = @select(f32, leftWall, old[y][x], leftRow);

            const rightWall = if (x == WIDTH / vecLen - 1)
                std.simd.shiftElementsLeft(walls[y][x], 1, true)
            else
                std.simd.shiftElementsLeft(walls[y][x], 1, walls[y][x + 1][0]);
            const nextFirst = if (x == WIDTH / vecLen - 1) old[y][x][vecLen - 1] else old[y][x + 1][0];
            const rightRow = std.simd.shiftElementsLeft(old[y][x], 1, nextFirst);
            const right = @select(f32, rightWall, old[y][x], rightRow);

            chunk.* = (top + btm + right + left - divergence[y][x]) / @as(vec, @splat(4.0));
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

    /// X is 0 on the leftmost edge
    /// Y is 0 at the center of the topmost cell
    fn bilinearX(self: *const MacGrid, x: f32, y: f32) f32 {
        const truncX: usize = @trunc(x);
        const truncY: usize = @trunc(y);
        if (y >= HEIGHT - 1.0) {
            const left = self.gridX[HEIGHT - 1][truncX];
            const right = self.gridX[HEIGHT - 1][truncX + 1];
            return right * (x - @trunc(x)) + left * (1.0 - x + @trunc(x));
        } else {
            const topLeft = self.gridX[truncY][truncX];
            const topRight = self.gridX[truncY][truncX + 1];
            const btmLeft = self.gridX[truncY + 1][truncX];
            const btmRight = self.gridX[truncY + 1][truncX + 1];

            const top = topRight * (x - @trunc(x)) + topLeft * (1.0 - x + @trunc(x));
            const btm = btmRight * (x - @trunc(x)) + btmLeft * (1.0 - x + @trunc(x));
            return btm * (y - @trunc(y)) + top * (1.0 - y + @trunc(y));
        }
    }

    /// X is 0 at the center of the leftmost cell
    /// Y is 0 on the topmost edge
    fn bilinearY(self: *const MacGrid, x: f32, y: f32) f32 {
        const truncX: usize = @trunc(x);
        const truncY: usize = @trunc(y);
        if (x >= WIDTH - 1.0) {
            const top = self.gridY[truncY][WIDTH - 1];
            const btm = self.gridY[truncY + 1][WIDTH - 1];
            return btm * (y - @trunc(y)) + top * (1.0 - y + @trunc(y));
        } else {
            const topLeft = self.gridY[truncY][truncX];
            const topRight = self.gridY[truncY][truncX + 1];
            const btmLeft = self.gridY[truncY + 1][truncX];
            const btmRight = self.gridY[truncY + 1][truncX + 1];

            const top = topRight * (x - @trunc(x)) + topLeft * (1.0 - x + @trunc(x));
            const btm = btmRight * (x - @trunc(x)) + btmLeft * (1.0 - x + @trunc(x));
            return btm * (y - @trunc(y)) + top * (1.0 - y + @trunc(y));
        }
    }

    fn drawArrows(self: *MacGrid) void {
        for (0..HEIGHT) |y| {
            for (0..WIDTH) |x| {
                const xComp = 0.5 * (self.gridX[y][x] + self.gridX[y][x + 1]) * SCALE;
                const yComp = 0.5 * (self.gridY[y][x] + self.gridY[y + 1][x]) * SCALE;
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

    fn drawColor(self: *MacGrid) void {
        for (0..HEIGHT) |y| {
            for (0..WIDTH) |x| {
                const xComp = (self.gridX[y][x] + self.gridX[y][x + 1]);
                const yComp = (self.gridY[y][x] + self.gridY[y + 1][x]);
                const angle = std.math.atan2(yComp, xComp) + std.math.pi;

                const h6 = angle * 6.0 / std.math.tau;
                const r = @abs(h6 - 3.0) - 1.0;
                const g = 2.0 - @abs(h6 - 2.0);
                const b = 2.0 - @abs(h6 - 4.0);

                const color = rl.colorFromNormalized(.{
                    .x = std.math.clamp(r, 0.0, 1.0),
                    .y = std.math.clamp(g, 0.0, 1.0),
                    .z = std.math.clamp(b, 0.0, 1.0),
                    .w = std.math.clamp(@sqrt(@abs(xComp) + @abs(yComp)) * 0.5, 0.0, 1.0),
                });

                rl.drawRectangleV(.{ .x = @as(f32, @floatFromInt(x)) * SCALE, .y = @as(f32, @floatFromInt(y)) * SCALE }, .{ .x = SCALE, .y = SCALE }, color);
            }
        }
    }

    fn drawStreamlines(self: *MacGrid) void {
        for (0..HEIGHT) |y| {
            for (0..WIDTH) |x| {
                var xPos = @as(f32, @floatFromInt(x)) + 0.5;
                var yPos = @as(f32, @floatFromInt(y)) + 0.5;
                var length: f32 = 0.0;
                var points: [32]rl.Vector2 = undefined;
                const len = for (&points, 0..) |*point, count| {
                    if (length >= 5.0) {
                        break count;
                    }
                    point.* = rl.Vector2{ .x = xPos * SCALE, .y = yPos * SCALE };
                    const xComp = self.bilinearX(xPos, yPos - 0.5) * 0.5;
                    const yComp = self.bilinearY(xPos - 0.5, yPos) * 0.5;
                    length += @abs(xComp) + @abs(yComp);
                    xPos += xComp;
                    yPos += yComp;
                } else points.len;
                rl.drawLineStrip(points[0..len], .black);
            }
        }
    }
};

fn drawPressure(pressure: *const Grid) void {
    for (0..HEIGHT) |y| {
        for (0..WIDTH) |x| {
            const color = if (pressure[y][x] >= 0) rl.Color.blue else rl.Color.red;
            rl.drawRectangleV(
                .{ .x = @as(f32, @floatFromInt(x)) * SCALE, .y = @as(f32, @floatFromInt(y)) * SCALE },
                .{ .x = SCALE, .y = SCALE },
                color.alpha(10.0 * @abs(pressure[y][x])),
            );
        }
    }
}

fn project(vel: *MacGrid, pressure: *const Grid, walls: *const WallGrid) void {
    for (&vel.gridX, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            if (x == 0 or x == WIDTH or walls[y].isSet(x - 1) or walls[y].isSet(x)) continue;
            const left = pressure[y][x - 1];
            const right = pressure[y][x];
            cell.* -= right - left;
        }
    }
    for (&vel.gridY, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            if (y == 0 or y == HEIGHT or walls[y - 1].isSet(x) or walls[y].isSet(x)) continue;
            const top = pressure[y - 1][x];
            const btm = pressure[y][x];
            cell.* -= btm - top;
        }
    }
}

fn advect(vel: *MacGrid) void {
    const old = vel.*;
    for (&vel.gridX, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            if (cell.* == 0 or x == 0 or x == WIDTH) continue;

            const posX: f32 = @floatFromInt(x);
            const posY: f32 = @floatFromInt(y);

            const dX = old.gridX[y][x];
            const dY = blk: {
                const topLeft = old.gridY[y][x - 1];
                const topRight = old.gridY[y][x];
                const btmLeft = old.gridY[y + 1][x - 1];
                const btmRight = old.gridY[y + 1][x];
                break :blk (topLeft + topRight + btmLeft + btmRight) * 0.25;
            };

            const backX = posX - dX * DT;
            const backY = posY - dY * DT;
            cell.* = old.bilinearX(backX, backY);
        }
    }

    for (&vel.gridY, 0..) |*row, y| {
        for (row, 0..) |*cell, x| {
            if (cell.* == 0) continue;

            const posX: f32 = @floatFromInt(x);
            const posY: f32 = @floatFromInt(y);

            const dX = blk: {
                const btmLeft = old.gridX[y][x];
                const topLeft = old.gridX[y - 1][x];
                const btmRight = old.gridX[y][x + 1];
                const topRight = old.gridX[y - 1][x + 1];
                break :blk (topLeft + topRight + btmLeft + btmRight) * 0.25;
            };
            const dY = old.gridY[y][x];

            const backX = posX - dX * DT;
            const backY = posY - dY * DT;
            cell.* = old.bilinearY(backX, backY);
        }
    }
}

pub fn main(init: std.process.Init) !void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;

    rl.setConfigFlags(.{ .vsync_hint = true, .fullscreen_mode = true });
    rl.initWindow(screenWidth, screenHeight, "Fluid Sim");
    defer rl.closeWindow();

    //--------------------------------------------------------------------------------------

    var vel: MacGrid = .zeroes();
    var div: Grid align(@alignOf(vec)) = @splat(@splat(0.0));
    var pressure: Grid align(@alignOf(vec)) = @splat(@splat(0.0));
    var wallGrid: WallGrid = @splat(.empty);
    const clock = std.Io.Clock.awake;
    for (&vel.gridX) |*row| {
        row[0] = 1.0;
        row[WIDTH] = 1.0;
    }

    const DrawMode = enum(i32) {
        arrows = 0,
        streamlines,
        color,
        arrowcolor,
        streamlinecolor,
    };
    const MouseMode = enum(i32) {
        push = 0,
        wall,
    };
    var mouseMode: MouseMode = .push;
    var drawMode: DrawMode = .streamlinecolor;

    while (!rl.windowShouldClose()) {
        const pos = rl.getMousePosition();
        switch (mouseMode) {
            .push => {
                if (rl.isMouseButtonDown(.left)) {
                    const delta = rl.getMouseDelta();
                    const cellX, const cellY = vel.getCellPtrs(pos.x / SCALE, pos.y / SCALE);
                    cellX.* += delta.x / SCALE * 10.0;
                    cellY.* += delta.y / SCALE * 10.0;
                }
            },
            .wall => {
                if (rl.isMouseButtonDown(.left)) {
                    const x: usize = @round(pos.x / SCALE - 0.5);
                    const y: usize = @round(pos.y / SCALE - 0.5);
                    wallGrid[y].set(x);
                    vel.gridX[y][x] = 0;
                    vel.gridX[y][x + 1] = 0;
                    vel.gridY[y][x] = 0;
                    vel.gridY[y + 1][x] = 0;
                }
                if (rl.isMouseButtonDown(.right)) {
                    const x: usize = @round(pos.x / SCALE - 0.5);
                    const y: usize = @round(pos.y / SCALE - 0.5);
                    wallGrid[y].unset(x);
                }
            },
        }
        // Update
        //----------------------------------------------------------------------------------

        const updateStart = clock.now(init.io);
        for (0..10) |_| {
            calcDiv(&div, &vel);
            for (0..100) |_| {
                calcPressure(@ptrCast(&pressure), @ptrCast(&div), @ptrCast(&wallGrid));
            }
            project(&vel, &pressure, &wallGrid);
            advect(&vel);
        }
        pressure = @splat(@splat(0.0));
        const updateTime = updateStart.untilNow(init.io, clock);
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        const drawStart = clock.now(init.io);

        rl.clearBackground(.white);
        switch (drawMode) {
            .arrows => {
                vel.drawArrows();
            },
            .arrowcolor => {
                vel.drawColor();
                vel.drawArrows();
            },
            .color => {
                vel.drawColor();
            },
            .streamlinecolor => {
                vel.drawColor();
                vel.drawStreamlines();
            },
            .streamlines => {
                vel.drawStreamlines();
            },
        }
        // drawPressure(&pressure);
        for (wallGrid, 0..) |row, y| {
            var iter = row.iterator(.{});
            while (iter.next()) |x| {
                rl.drawRectangleV(
                    .{ .x = @as(f32, @floatFromInt(x)) * SCALE, .y = @as(f32, @floatFromInt(y)) * SCALE },
                    .{ .x = SCALE, .y = SCALE },
                    .black,
                );
            }
        }

        const drawTime = drawStart.untilNow(init.io, clock);

        rl.drawFPS(10, 0);
        {
            var buf: [16]u8 = std.mem.zeroes([16]u8);
            var writer = std.Io.Writer.fixed(&buf);
            try updateTime.format(&writer);
            rl.drawText(@ptrCast(&buf), 10, 30, 20, .red);
        }
        {
            var buf: [16]u8 = std.mem.zeroes([16]u8);
            var writer = std.Io.Writer.fixed(&buf);
            try drawTime.format(&writer);
            rl.drawText(@ptrCast(&buf), 10, 60, 20, .red);
        }
        _ = rg.comboBox(.init(10.0, 90.0, 150.0, 20.0), "Arrows;Streamlines;Color;Arrows and color;Streamlines and color", @ptrCast(&drawMode));
        _ = rg.comboBox(.init(10.0, 120.0, 150.0, 20.0), "Push fluid around;Place/remove walls", @ptrCast(&mouseMode));
        //----------------------------------------------------------------------------------
    }
}
