// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");
const options = @import("options");

pub fn getUserUid(
    io: std.Io,
    name: []const u8,
) !?u32 {
    var passwd_file = try std.Io.Dir.openFileAbsolute(io, "/etc/passwd", .{ .mode = .read_only });
    defer passwd_file.close(io);

    // room for 2 paths (home directory and shell) plus a generous amount for the rest
    var passwd_buf: [1024 + std.fs.max_path_bytes * 2]u8 = undefined;
    var passwd_file_reader = passwd_file.reader(io, &passwd_buf);
    const reader = &passwd_file_reader.interface;

    while (true) {
        const line = reader.takeDelimiter('\n') catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.StreamTooLong => return error.StreamTooLong,
        } orelse return null;
        var it = std.mem.splitScalar(u8, line, ':');
        const username = it.next() orelse continue;
        if (!std.mem.eql(u8, username, name)) continue;
        _ = it.next(); // skip password field
        const uid_str = it.next() orelse return error.MissingUID;
        return try std.fmt.parseUnsigned(u32, uid_str, 10);
    }
}

pub fn getUserGid(
    io: std.Io,
    name: []const u8,
) !?u32 {
    var passwd_file = try std.Io.Dir.openFileAbsolute(io, "/etc/passwd", .{ .mode = .read_only });
    defer passwd_file.close(io);

    // room for 2 paths (home directory and shell) plus a generous amount for the rest
    var passwd_buf: [1024 + std.fs.max_path_bytes * 2]u8 = undefined;
    var passwd_file_reader = passwd_file.reader(io, &passwd_buf);
    const reader = &passwd_file_reader.interface;

    while (true) {
        const line = reader.takeDelimiter('\n') catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.StreamTooLong => return error.StreamTooLong,
        } orelse return null;
        var it = std.mem.splitScalar(u8, line, ':');
        const username = it.next() orelse continue;
        if (!std.mem.eql(u8, username, name)) continue;
        _ = it.next(); // skip password field
        _ = it.next(); // skip uid field
        const gid_str = it.next() orelse return error.MissingGID;
        return try std.fmt.parseUnsigned(u32, gid_str, 10);
    }
}
