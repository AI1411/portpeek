const std = @import("std");
const proc_info = @import("proc_info");
const types = @import("types");

// テスト用に一時ディレクトリ上に /proc 風のディレクトリ構造を構築するヘルパー。
// proc_path/
//   <pid>/
//     comm   (プロセス名)
//     cmdline (NULL区切りのコマンドライン)
fn buildFakeProcEntry(tmp_dir: std.fs.Dir, pid: u32, comm: ?[]const u8, cmdline: ?[]const u8) !void {
    var pid_buf: [32]u8 = undefined;
    const pid_str = try std.fmt.bufPrint(&pid_buf, "{d}", .{pid});
    try tmp_dir.makePath(pid_str);
    var pid_dir = try tmp_dir.openDir(pid_str, .{});
    defer pid_dir.close();

    if (comm) |name| {
        const comm_file = try pid_dir.createFile("comm", .{});
        defer comm_file.close();
        try comm_file.writeAll(name);
    }

    if (cmdline) |args| {
        const cmdline_file = try pid_dir.createFile("cmdline", .{});
        defer cmdline_file.close();
        try cmdline_file.writeAll(args);
    }
}

test "readCommFromPath: プロセス名を取得（末尾改行なし）" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try buildFakeProcEntry(tmp.dir, 1234, "nginx", null);

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    const name = try proc_info.readCommFromPath(allocator, abs_path, 1234);
    defer allocator.free(name);

    try std.testing.expectEqualStrings("nginx", name);
}

test "readCommFromPath: プロセス名を取得（末尾改行あり）" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try buildFakeProcEntry(tmp.dir, 5678, "sshd\n", null);

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    const name = try proc_info.readCommFromPath(allocator, abs_path, 5678);
    defer allocator.free(name);

    try std.testing.expectEqualStrings("sshd", name);
}

test "readCommFromPath: ファイルが存在しない場合はエラー" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    const result = proc_info.readCommFromPath(allocator, abs_path, 9999);
    try std.testing.expectError(error.FileNotFound, result);
}

test "readCmdlineFromPath: NULL バイトをスペースに変換" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // "nginx\x00-c\x00/etc/nginx/nginx.conf\x00"
    try buildFakeProcEntry(tmp.dir, 1234, null, "nginx\x00-c\x00/etc/nginx/nginx.conf\x00");

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    const cmdline = try proc_info.readCmdlineFromPath(allocator, abs_path, 1234);
    defer allocator.free(cmdline);

    try std.testing.expectEqualStrings("nginx -c /etc/nginx/nginx.conf", cmdline);
}

test "readCmdlineFromPath: ファイルが存在しない場合は空文字列を返す" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    const cmdline = try proc_info.readCmdlineFromPath(allocator, abs_path, 9999);
    defer allocator.free(cmdline);

    try std.testing.expectEqualStrings("", cmdline);
}

test "readCmdlineFromPath: 単一引数（末尾 NULL のみ）" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try buildFakeProcEntry(tmp.dir, 42, null, "bash\x00");

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    const cmdline = try proc_info.readCmdlineFromPath(allocator, abs_path, 42);
    defer allocator.free(cmdline);

    try std.testing.expectEqualStrings("bash", cmdline);
}

test "resolveProcessInfoFromPath: pid が Some の PortEntry に process_name と cmdline を付与" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try buildFakeProcEntry(tmp.dir, 100, "python3\n", "python3\x00/app/main.py\x00");

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
            .inode = 1111,
            .pid = 100,
            .process_name = null,
            .cmdline = null,
            .uid = 1000,
            .is_ipv6 = false,
        },
    };

    try proc_info.resolveProcessInfoFromPath(allocator, &entries, abs_path);
    defer {
        if (entries[0].process_name) |n| allocator.free(n);
        if (entries[0].cmdline) |c| allocator.free(c);
    }

    try std.testing.expectEqualStrings("python3", entries[0].process_name.?);
    try std.testing.expectEqualStrings("python3 /app/main.py", entries[0].cmdline.?);
}

test "resolveProcessInfoFromPath: pid が null の PortEntry はスキップ" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    var entries = [_]types.PortEntry{
        .{
            .protocol = .tcp,
            .local_addr = .{ 0, 0, 0, 0 },
            .local_addr6 = .{0} ** 16,
            .local_port = 9090,
            .remote_addr = .{ 0, 0, 0, 0 },
            .remote_addr6 = .{0} ** 16,
            .remote_port = 0,
            .state = .listen,
            .inode = 2222,
            .pid = null,
            .process_name = null,
            .cmdline = null,
            .uid = 0,
            .is_ipv6 = false,
        },
    };

    try proc_info.resolveProcessInfoFromPath(allocator, &entries, abs_path);

    try std.testing.expect(entries[0].process_name == null);
    try std.testing.expect(entries[0].cmdline == null);
}

test "resolveProcessInfoFromPath: proc ファイルが存在しない PID は process_name が null" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    var entries = [_]types.PortEntry{
        .{
            .protocol = .tcp,
            .local_addr = .{ 0, 0, 0, 0 },
            .local_addr6 = .{0} ** 16,
            .local_port = 443,
            .remote_addr = .{ 0, 0, 0, 0 },
            .remote_addr6 = .{0} ** 16,
            .remote_port = 0,
            .state = .listen,
            .inode = 3333,
            .pid = 9999, // このPIDのディレクトリは存在しない
            .process_name = null,
            .cmdline = null,
            .uid = 0,
            .is_ipv6 = false,
        },
    };

    try proc_info.resolveProcessInfoFromPath(allocator, &entries, abs_path);
    defer {
        if (entries[0].cmdline) |c| allocator.free(c);
    }

    try std.testing.expect(entries[0].process_name == null);
}

test "resolveProcessInfoFromPath: 再実行時に旧アロケーションが解放されメモリリークしない" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try buildFakeProcEntry(tmp.dir, 200, "first\n", "first\x00arg\x00");

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
            .inode = 4444,
            .pid = 200,
            .process_name = null,
            .cmdline = null,
            .uid = 1000,
            .is_ipv6 = false,
        },
    };

    // 1回目の呼び出し
    try proc_info.resolveProcessInfoFromPath(allocator, &entries, abs_path);
    try std.testing.expectEqualStrings("first", entries[0].process_name.?);

    // proc ファイルを更新
    try buildFakeProcEntry(tmp.dir, 200, "second\n", "second\x00arg\x00");

    // 2回目の呼び出し: 旧バッファが解放されて新しい値に更新される
    // std.testing.allocator がリークを検出するためリークがあればテスト失敗になる
    try proc_info.resolveProcessInfoFromPath(allocator, &entries, abs_path);
    defer {
        if (entries[0].process_name) |n| allocator.free(n);
        if (entries[0].cmdline) |c| allocator.free(c);
    }

    try std.testing.expectEqualStrings("second", entries[0].process_name.?);
    try std.testing.expectEqualStrings("second arg", entries[0].cmdline.?);
}

test "resolveProcessInfoFromPath: pid が null になった PortEntry の旧フィールドがリセットされる" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try buildFakeProcEntry(tmp.dir, 300, "daemon\n", "daemon\x00--run\x00");

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    var entries = [_]types.PortEntry{
        .{
            .protocol = .tcp,
            .local_addr = .{ 0, 0, 0, 0 },
            .local_addr6 = .{0} ** 16,
            .local_port = 22,
            .remote_addr = .{ 0, 0, 0, 0 },
            .remote_addr6 = .{0} ** 16,
            .remote_port = 0,
            .state = .listen,
            .inode = 5555,
            .pid = 300,
            .process_name = null,
            .cmdline = null,
            .uid = 0,
            .is_ipv6 = false,
        },
    };

    // 1回目: pid=300 でフィールドを付与
    try proc_info.resolveProcessInfoFromPath(allocator, &entries, abs_path);
    try std.testing.expectEqualStrings("daemon", entries[0].process_name.?);

    // pid を null に変更して再実行
    entries[0].pid = null;
    try proc_info.resolveProcessInfoFromPath(allocator, &entries, abs_path);

    // 旧アロケーションが解放されて null にリセットされる
    try std.testing.expect(entries[0].process_name == null);
    try std.testing.expect(entries[0].cmdline == null);
}

test "readCmdlineFromPath: 末尾が空白の引数を保持する" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // "echo\x00foo \x00" — 最後の引数 "foo " は末尾に空白を含む
    try buildFakeProcEntry(tmp.dir, 777, null, "echo\x00foo \x00");

    const abs_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(abs_path);

    const cmdline = try proc_info.readCmdlineFromPath(allocator, abs_path, 777);
    defer allocator.free(cmdline);

    // 末尾の空白が保持されていること
    try std.testing.expectEqualStrings("echo foo ", cmdline);
}
