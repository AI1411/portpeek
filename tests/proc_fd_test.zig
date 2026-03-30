const std = @import("std");
const proc_fd = @import("proc_fd");
const types = @import("types");

// テスト用に一時ディレクトリ上に /proc 風のディレクトリ構造を構築するヘルパー。
// proc_path/
//   <pid>/
//     fd/
//       0 -> socket:[inode]  (symlink)
fn buildFakeProcDir(tmp_dir: std.fs.Dir, pid: u32, fd_num: u32, target: []const u8) !void {
    var pid_buf: [32]u8 = undefined;
    const pid_str = try std.fmt.bufPrint(&pid_buf, "{d}", .{pid});
    try tmp_dir.makePath(pid_str);
    var pid_dir = try tmp_dir.openDir(pid_str, .{});
    defer pid_dir.close();

    try pid_dir.makePath("fd");
    var fd_dir = try pid_dir.openDir("fd", .{});
    defer fd_dir.close();

    var fd_buf: [32]u8 = undefined;
    const fd_str = try std.fmt.bufPrint(&fd_buf, "{d}", .{fd_num});
    try fd_dir.symLink(target, fd_str, .{});
}

test "buildInodePidMapFromPath: socket:[inode] シンボリックリンクをマッピング" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // PID 1234, fd 0 -> socket:[99001]
    try buildFakeProcDir(tmp.dir, 1234, 0, "socket:[99001]");

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    var map = try proc_fd.buildInodePidMapFromPath(allocator, abs_path);
    defer map.deinit();

    try std.testing.expectEqual(@as(?u32, 1234), map.get(99001));
}

test "buildInodePidMapFromPath: socket以外のシンボリックリンクは無視" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // pipe:[12345] は無視される
    try buildFakeProcDir(tmp.dir, 5678, 0, "pipe:[12345]");

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    var map = try proc_fd.buildInodePidMapFromPath(allocator, abs_path);
    defer map.deinit();

    try std.testing.expectEqual(@as(usize, 0), map.count());
}

test "buildInodePidMapFromPath: 数字以外のディレクトリは無視" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // "net" ディレクトリは PID として扱われない
    try tmp.dir.makeDir("net");

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    var map = try proc_fd.buildInodePidMapFromPath(allocator, abs_path);
    defer map.deinit();

    try std.testing.expectEqual(@as(usize, 0), map.count());
}

test "buildInodePidMapFromPath: 同一 inode は最小 PID を採用" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // PID 100 と PID 200 が同じ inode を持つ場合、最小 PID (100) が採用される
    try buildFakeProcDir(tmp.dir, 100, 0, "socket:[77777]");
    try buildFakeProcDir(tmp.dir, 200, 0, "socket:[77777]");

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    var map = try proc_fd.buildInodePidMapFromPath(allocator, abs_path);
    defer map.deinit();

    try std.testing.expectEqual(@as(?u32, 100), map.get(77777));
}

test "buildInodePidMapFromPath: 複数 PID・複数 fd のマッピング" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // PID 10: fd 3 -> socket:[1001], fd 4 -> socket:[1002]
    try buildFakeProcDir(tmp.dir, 10, 3, "socket:[1001]");
    try buildFakeProcDir(tmp.dir, 10, 4, "socket:[1002]");
    // PID 20: fd 5 -> socket:[2001]
    try buildFakeProcDir(tmp.dir, 20, 5, "socket:[2001]");

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    var map = try proc_fd.buildInodePidMapFromPath(allocator, abs_path);
    defer map.deinit();

    try std.testing.expectEqual(@as(?u32, 10), map.get(1001));
    try std.testing.expectEqual(@as(?u32, 10), map.get(1002));
    try std.testing.expectEqual(@as(?u32, 20), map.get(2001));
}

test "resolvePidsFromPath: inode が一致する PortEntry に pid を付与" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try buildFakeProcDir(tmp.dir, 42, 0, "socket:[9999]");

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    var entries = [_]types.PortEntry{
        .{
            .protocol = .tcp,
            .local_addr = .{ 0, 0, 0, 0 },
            .local_addr6 = .{0} ** 16,
            .local_port = 8080,
            .remote_addr = .{ 0, 0, 0, 0 },
            .remote_addr6 = .{0} ** 16,
            .remote_port = 0,
            .state = .listen,
            .inode = 9999,
            .pid = null,
            .process_name = null,
            .cmdline = null,
            .uid = 1000,
            .is_ipv6 = false,
        },
    };

    try proc_fd.resolvePidsFromPath(allocator, &entries, abs_path);

    try std.testing.expectEqual(@as(?u32, 42), entries[0].pid);
}

test "resolvePidsFromPath: inode が一致しない PortEntry の pid は null になる" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // inode 9999 は登録しない
    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    var entries = [_]types.PortEntry{
        .{
            .protocol = .tcp,
            .local_addr = .{ 0, 0, 0, 0 },
            .local_addr6 = .{0} ** 16,
            .local_port = 8080,
            .remote_addr = .{ 0, 0, 0, 0 },
            .remote_addr6 = .{0} ** 16,
            .remote_port = 0,
            .state = .listen,
            .inode = 9999,
            .pid = 999, // 既存の pid を設定しておく
            .process_name = null,
            .cmdline = null,
            .uid = 1000,
            .is_ipv6 = false,
        },
    };

    try proc_fd.resolvePidsFromPath(allocator, &entries, abs_path);

    // マップにない inode は null にリセットされる
    try std.testing.expectEqual(@as(?u32, null), entries[0].pid);
}
