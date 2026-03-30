const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "portsnap",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const hex_mod = b.createModule(.{
        .root_source_file = b.path("src/utils/hex.zig"),
        .target = target,
        .optimize = optimize,
    });

    const types_mod = b.createModule(.{
        .root_source_file = b.path("src/scanner/types.zig"),
        .target = target,
        .optimize = optimize,
    });

    const proc_net_mod = b.createModule(.{
        .root_source_file = b.path("src/scanner/proc_net.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "hex", .module = hex_mod },
        },
    });

    const proc_fd_mod = b.createModule(.{
        .root_source_file = b.path("src/scanner/proc_fd.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests/proc_net_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "hex", .module = hex_mod },
            .{ .name = "proc_net", .module = proc_net_mod },
            .{ .name = "types", .module = types_mod },
        },
    });

    const proc_fd_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/proc_fd_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "proc_fd", .module = proc_fd_mod },
            .{ .name = "types", .module = types_mod },
        },
    });

    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const proc_fd_tests = b.addTest(.{
        .root_module = proc_fd_test_mod,
    });
    const run_proc_fd_tests = b.addRunArtifact(proc_fd_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_proc_fd_tests.step);
}
