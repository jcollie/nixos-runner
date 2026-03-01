// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");
const options = @import("options");

pub fn chdir(
    user: enum { root, user },
) void {
    _ = std.os.linux.chdir(switch (user) {
        .root => "/root",
        .user => "/github/home",
    });
}
