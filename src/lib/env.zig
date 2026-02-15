// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");
const options = @import("options");

pub fn fixupEnvironMap(alloc: std.mem.Allocator, old: *const std.process.Environ.Map) (std.mem.Allocator.Error || std.Io.Writer.Error)!std.process.Environ.Map {
    var new = try old.clone(alloc);
    errdefer new.deinit();

    path: {
        const path = new.get("PATH") orelse break :path;

        var it = std.mem.splitScalar(u8, path, ':');

        _ = it.next();

        var index: usize = 0;

        var writer: std.Io.Writer.Allocating = .init(alloc);
        defer writer.deinit();

        while (it.next()) |entry| : (index += 1) {
            if (index != 0) try writer.writer.writeByte(':');
            try writer.writer.writeAll(entry);
        }

        try new.put("PATH", writer.written());
    }

    try new.put("USER", options.username);

    return new;
}
