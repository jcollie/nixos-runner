// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");

pub const chdir = @import("lib/chdir.zig").chdir;
pub const exec = @import("lib/process.zig").exec;
pub const fixupEnvironMap = @import("lib/env.zig").fixupEnvironMap;
pub const switchToUser = @import("lib/switchtouser.zig").switchToUser;

test {
    _ = @import("lib/chdir.zig");
    _ = @import("lib/env.zig");
    _ = @import("lib/process.zig");
    _ = @import("lib/switchtouser.zig");
}
