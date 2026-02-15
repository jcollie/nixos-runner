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

    nix: {
        if (!std.mem.eql(u8, init.environ_map.get("CI") orelse break :nix, "true")) break :nix;
        if (!std.mem.eql(u8, init.environ_map.get("GITHUB_ACTIONS") orelse break :nix, "true")) break :nix;

        var it = try init.minimal.args.iterateAllocator(arena);
        defer it.deinit();

        if (!std.mem.eql(u8, it.next() orelse break :nix, "tail")) break :nix;
        if (!std.mem.eql(u8, it.next() orelse break :nix, "-f")) break :nix;
        if (!std.mem.eql(u8, it.next() orelse break :nix, "/dev/null")) break :nix;
        if (it.next() != null) break :nix;

        cwd: {
            var dir = std.Io.Dir.openDirAbsolute(io, "/", .{}) catch break :cwd;
            defer dir.close(io);
            std.process.setCurrentDir(io, dir) catch break :cwd;
        }

        const err = std.process.replace(io, .{
            .argv = &.{
                options.nix,
                "daemon",
                "--trusted",
            },
            .environ_map = &environ_map,
        });

        std.debug.print("unable to execute: {t}\n", .{err});
        return;
    }

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(arena);

    try argv.append(arena, options.tail);

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
