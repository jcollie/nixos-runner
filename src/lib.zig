// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");

pub const fixupEnvironMap = @import("lib/env.zig").fixupEnvironMap;
pub const switchToUser = @import("lib/switchtouser.zig").switchToUser;

test {
    _ = @import("lib/env.zig");
    _ = @import("lib/switchtouser.zig");
}
