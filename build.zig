const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── 共有モジュール定義 ─────────────────────────────────────────
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

    const color_mod = b.createModule(.{
        .root_source_file = b.path("src/utils/color.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
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

    const proc_info_mod = b.createModule(.{
        .root_source_file = b.path("src/scanner/proc_info.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    const port_filter_mod = b.createModule(.{
        .root_source_file = b.path("src/filter/port.zig"),
        .target = target,
        .optimize = optimize,
    });

    const process_filter_mod = b.createModule(.{
        .root_source_file = b.path("src/filter/process.zig"),
        .target = target,
        .optimize = optimize,
    });

    const state_filter_mod = b.createModule(.{
        .root_source_file = b.path("src/filter/state.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    const table_mod = b.createModule(.{
        .root_source_file = b.path("src/output/table.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "color", .module = color_mod },
        },
    });

    // ── 実行ファイル ──────────────────────────────────────────────
    const exe = b.addExecutable(.{
        .name = "portsnap",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "types", .module = types_mod },
                .{ .name = "proc_net", .module = proc_net_mod },
                .{ .name = "proc_fd", .module = proc_fd_mod },
                .{ .name = "proc_info", .module = proc_info_mod },
                .{ .name = "table", .module = table_mod },
            },
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

    // ── テスト ──────────────────────────────────────────────────
    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests/proc_net_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "hex", .module = hex_mod },
            .{ .name = "proc_net", .module = proc_net_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "port_filter", .module = port_filter_mod },
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

    const proc_info_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/proc_info_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "proc_info", .module = proc_info_mod },
            .{ .name = "types", .module = types_mod },
        },
    });

    const color_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/color_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "color", .module = color_mod },
            .{ .name = "types", .module = types_mod },
        },
    });

    const table_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/table_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "table", .module = table_mod },
        },
    });

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const proc_fd_tests = b.addTest(.{ .root_module = proc_fd_test_mod });
    const run_proc_fd_tests = b.addRunArtifact(proc_fd_tests);

    const proc_info_tests = b.addTest(.{ .root_module = proc_info_test_mod });
    const run_proc_info_tests = b.addRunArtifact(proc_info_tests);

    const color_tests = b.addTest(.{ .root_module = color_test_mod });
    const run_color_tests = b.addRunArtifact(color_tests);

    const table_tests = b.addTest(.{ .root_module = table_test_mod });
    const run_table_tests = b.addRunArtifact(table_tests);

    const filter_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/filter_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "process_filter", .module = process_filter_mod },
            .{ .name = "state_filter", .module = state_filter_mod },
            .{ .name = "types", .module = types_mod },
        },
    });
    const filter_tests = b.addTest(.{ .root_module = filter_test_mod });
    const run_filter_tests = b.addRunArtifact(filter_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_proc_fd_tests.step);
    test_step.dependOn(&run_proc_info_tests.step);
    test_step.dependOn(&run_color_tests.step);
    test_step.dependOn(&run_table_tests.step);
    test_step.dependOn(&run_filter_tests.step);
}
