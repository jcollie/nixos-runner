// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");
const options = @import("options");

const lib = @import("lib.zig");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    var environ_map = try lib.fixupEnvironMap(arena, init.environ_map);
    defer environ_map.deinit();

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(arena);

    try argv.append(arena, options.bash);

    var it = try init.minimal.args.iterateAllocator(arena);
    defer it.deinit();

    _ = it.next();
    while (it.next()) |arg| {
        try argv.append(arena, arg);
    }

    try lib.setUID();

    const err = std.process.replace(io, .{
        .argv = argv.items,
        .environ_map = &environ_map,
    });

    std.debug.print("unable to execute: {t}\n", .{err});
}
