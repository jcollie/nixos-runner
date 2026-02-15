// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");
const options = @import("options");

pub fn setUID() !void {
    const rc = std.os.linux.setuid(options.uid);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => return,
        .PERM => return error.NoPermission,
        else => |err| {
            std.debug.print("unexpected error: {t}\n", .{err});
            return error.UnexpectedError;
        },
    }
}
