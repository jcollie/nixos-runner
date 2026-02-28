// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const alloc: std.mem.Allocator = init.arena.allocator();
    while (true) {
        _ = try alloc.alloc(u8, 1024 * 1024);
        std.debug.print("Capacity: {Bi}\n", .{init.arena.queryCapacity()});
    }
}
