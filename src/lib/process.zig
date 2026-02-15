// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");
const options = @import("options");

pub fn exec(gpa: std.mem.Allocator, path: []const u8, argv: []const []const u8, map: *const std.process.Environ.Map) !void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const path0 = try alloc.dupeZ(u8, path);

    const argv0 = try alloc.allocSentinel(?[*:0]const u8, argv.len, null);
    for (argv, 0..) |arg, i| argv0[i] = (try alloc.dupeZ(u8, arg)).ptr;

    const block = try map.createPosixBlock(alloc, .{ .zig_progress_fd = -1 });

    const rc = std.os.linux.execve(
        path0.ptr,
        argv0.ptr,
        block,
    );

    return std.posix.unexpectedErrno(rc);
}
