// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");
const options = @import("options");

const lib = @import("lib.zig");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    try lib.switchToUser();

    var argv: std.ArrayList([]const u8) = .empty;

    var it = try init.minimal.args.iterateAllocator(arena);
    _ = it.next();

    while (it.next()) |arg| {
        try argv.append(arena, arg);
    }

    const err = std.process.replace(io, .{
        .argv = argv.items,
    });

    std.debug.print("unable to execute: {t}\n", .{err});
}
