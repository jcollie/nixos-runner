// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");
const options = @import("options");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    const rc = std.os.linux.setuid(options.uid);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {},
        else => |err| return std.posix.unexpectedErrno(err),
    }

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
