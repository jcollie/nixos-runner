// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");
const options = @import("options");

const lib = @import("lib.zig");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    nix: {
        if (!std.mem.eql(u8, init.environ_map.get("CI") orelse break :nix, "true")) break :nix;
        if (!std.mem.eql(u8, init.environ_map.get("GITHUB_ACTIONS") orelse break :nix, "true")) break :nix;

        var it = try init.minimal.args.iterateAllocator(arena);
        defer it.deinit();

        if (!std.mem.eql(u8, it.next() orelse break :nix, "tail")) break :nix;
        if (!std.mem.eql(u8, it.next() orelse break :nix, "-f")) break :nix;
        if (!std.mem.eql(u8, it.next() orelse break :nix, "/dev/null")) break :nix;
        if (it.next() != null) break :nix;

        var environ_map = try lib.fixupEnvironMap(arena, init.environ_map, .root);
        defer environ_map.deinit();

        cwd: {
            var dir = std.Io.Dir.openDirAbsolute(io, "/", .{}) catch break :cwd;
            defer dir.close(io);
            std.process.setCurrentDir(io, dir) catch break :cwd;
        }

        const err = std.process.replace(io, .{
            .argv = &.{
                options.nix,
                "daemon",
            },
            .environ_map = &environ_map,
        });

        std.debug.print("unable to execute: {t}\n", .{err});
        return;
    }

    var environ_map = try lib.fixupEnvironMap(arena, init.environ_map, .user);
    defer environ_map.deinit();

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(arena);

    try argv.append(arena, options.tail);

    var it = try init.minimal.args.iterateAllocator(arena);
    defer it.deinit();

    _ = it.next();
    while (it.next()) |arg| {
        try argv.append(arena, arg);
    }

    try lib.switchToUser();

    const err = std.process.replace(io, .{
        .argv = argv.items,
        .environ_map = &environ_map,
    });

    std.debug.print("unable to execute: {t}\n", .{err});
}
