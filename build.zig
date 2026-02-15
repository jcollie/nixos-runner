// SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
// SPDX-License-Identifier: MIT

const std = @import("std");

pub fn find(b: *std.Build, name: []const u8) ![]const u8 {
    const path = b.graph.environ_map.get("PATH") orelse return error.NoPath;
    var it = std.mem.splitScalar(u8, path, ':');
    while (it.next()) |entry| {
        if (entry.len == 0 or entry[0] != '/') continue;
        var dir = std.Io.Dir.openDirAbsolute(b.graph.io, entry, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => |e| return e,
        };
        defer dir.close(b.graph.io);
        const stat = dir.statFile(b.graph.io, name, .{ .follow_symlinks = false }) catch |err| switch (err) {
            error.FileNotFound => continue,
            error.NotDir => continue,
            else => |e| return e,
        };
        switch (stat.kind) {
            .file => return try std.fs.path.join(b.allocator, &.{ entry, name }),
            .sym_link => {
                var link: []const u8 = try std.fs.path.resolve(b.allocator, &.{ entry, name });
                while (true) {
                    var buf: [std.fs.max_path_bytes]u8 = undefined;
                    const len = try dir.readLink(b.graph.io, link, &buf);
                    link = try std.fs.path.resolve(b.allocator, &.{ std.fs.path.dirname(link) orelse link, buf[0..len] });
                    const new_stat = dir.statFile(b.graph.io, link, .{ .follow_symlinks = false }) catch |err| switch (err) {
                        error.FileNotFound => continue,
                        error.NotDir => continue,
                        else => |e| return e,
                    };
                    switch (new_stat.kind) {
                        .file => return link,
                        .sym_link => continue,
                        else => return error.NotAFile,
                    }
                }
            },
            else => return error.NotAFile,
        }
    }
    return error.FileNotFound;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run tests");

    const uid = b.option(u32, "uid", "uid to run as") orelse 1001;
    const gid = b.option(u32, "gid", "gid to run as") orelse 1001;
    const groups = b.option([]const u8, "groups", "list of supplemental groups") orelse "1001";
    const username = b.option([]const u8, "username", "username to run as") orelse "github";
    const tail = tail: {
        const tail = b.option([]const u8, "tail", "real tail binary") orelse try find(b, "tail");
        if (!std.mem.eql(u8, std.fs.path.basename(tail), "coreutils")) break :tail tail;
        const dir = std.fs.path.dirname(tail) orelse break :tail tail;
        break :tail try std.fs.path.join(b.allocator, &.{ dir, "tail" });
    };
    const nix = b.option([]const u8, "nix", "real nix binary") orelse try find(b, "nix");
    const bash = b.option([]const u8, "bash", "real bash binary") orelse try find(b, "bash");

    const options = b.addOptions();
    options.addOption(u32, "uid", uid);
    options.addOption(u32, "gid", gid);
    options.addOption([]const u32, "groups", groups: {
        var list: std.ArrayList(u32) = .empty;
        var it = std.mem.splitScalar(u8, groups, ',');
        while (it.next()) |v| {
            const g = try std.fmt.parseUnsigned(u32, v, 10);
            try list.append(b.allocator, g);
        }
        break :groups list.items;
    });
    options.addOption([]const u8, "username", username);
    options.addOption([]const u8, "tail", tail);
    options.addOption([]const u8, "nix", nix);
    options.addOption([]const u8, "bash", bash);

    const execas_exe = b.addExecutable(.{
        .name = b.fmt("execas-{d}", .{uid}),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/execas.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = false,
        .use_lld = false,
    });
    execas_exe.root_module.addOptions("options", options);
    b.installArtifact(execas_exe);

    const execas_tests = b.addTest(.{
        .root_module = execas_exe.root_module,
    });
    const run_execas_tests = b.addRunArtifact(execas_tests);
    test_step.dependOn(&run_execas_tests.step);

    const tail_exe = b.addExecutable(.{
        .name = "tail",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tail.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = false,
        .use_lld = false,
    });
    tail_exe.root_module.addOptions("options", options);

    b.installArtifact(tail_exe);

    const tail_tests = b.addTest(.{
        .root_module = tail_exe.root_module,
    });

    const run_tail_tests = b.addRunArtifact(tail_tests);
    test_step.dependOn(&run_tail_tests.step);

    const bash_exe = b.addExecutable(.{
        .name = "bash",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bash.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = false,
        .use_lld = false,
    });
    bash_exe.root_module.addOptions("options", options);

    b.installArtifact(bash_exe);

    const bash_tests = b.addTest(.{
        .root_module = tail_exe.root_module,
    });

    const run_bash_tests = b.addRunArtifact(bash_tests);
    test_step.dependOn(&run_bash_tests.step);
}
