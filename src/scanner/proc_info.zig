// src/scanner/proc_info.zig
// /proc/[pid]/comm と /proc/[pid]/cmdline を読み込んでプロセス情報を解決する。

const std = @import("std");
const types = @import("types");

/// 指定した proc_path から /proc/[pid]/comm を読んでプロセス名を返す（テスト用）。
/// 末尾の改行文字は除去する。呼び出し元が返り値を free する責任を持つ。
pub fn readCommFromPath(allocator: std.mem.Allocator, proc_path: []const u8, pid: u32) ![]const u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{d}/comm", .{ proc_path, pid });

    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 4096);
    errdefer allocator.free(content);

    // 末尾の改行を除去
    const trimmed = std.mem.trimRight(u8, content, "\n\r");
    if (trimmed.len == content.len) return content;

    const result = try allocator.dupe(u8, trimmed);
    allocator.free(content);
    return result;
}

/// /proc/[pid]/comm を読んでプロセス名を返す。
/// 末尾の改行文字は除去する。呼び出し元が返り値を free する責任を持つ。
pub fn readComm(allocator: std.mem.Allocator, pid: u32) ![]const u8 {
    return readCommFromPath(allocator, "/proc", pid);
}

/// 指定した proc_path から /proc/[pid]/cmdline を読んで NULL バイトをスペースに変換して返す（テスト用）。
/// ファイルが存在しない・アクセスできない場合は空文字列を返す。
/// OutOfMemory / StreamTooLong などの深刻なエラーは呼び出し元へ伝播する。
/// 呼び出し元が返り値を free する責任を持つ。
pub fn readCmdlineFromPath(allocator: std.mem.Allocator, proc_path: []const u8, pid: u32) ![]const u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{d}/cmdline", .{ proc_path, pid });

    const file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return allocator.dupe(u8, ""),
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 65536);
    errdefer allocator.free(content);

    // 末尾の連続する \0 の開始位置を求める。
    // NUL→空白変換の前に除去することで、最後の引数が空白で終わる場合を保持できる。
    var end = content.len;
    while (end > 0 and content[end - 1] == 0) {
        end -= 1;
    }

    // 末尾 \0 より前の NUL をスペースに変換
    for (content[0..end]) |*c| {
        if (c.* == 0) c.* = ' ';
    }

    if (end == content.len) return content;

    const result = try allocator.dupe(u8, content[0..end]);
    allocator.free(content);
    return result;
}

/// /proc/[pid]/cmdline を読んで NULL バイトをスペースに変換して返す。
/// ファイルが存在しない・アクセスできない場合は空文字列を返す。
/// 呼び出し元が返り値を free する責任を持つ。
pub fn readCmdline(allocator: std.mem.Allocator, pid: u32) ![]const u8 {
    return readCmdlineFromPath(allocator, "/proc", pid);
}

/// 指定した proc_path を使い、各 PortEntry の process_name と cmdline を更新する（テスト用）。
/// pid が Some の場合はファイルから読み取って付与し、None の場合は null にリセットする。
/// 再実行時は既存のアロケーションを解放してから上書きするため、二重解放やリークは発生しない。
/// 付与した文字列はすべて allocator で確保され、呼び出し元が管理する責任を持つ。
pub fn resolveProcessInfoFromPath(allocator: std.mem.Allocator, entries: []types.PortEntry, proc_path: []const u8) !void {
    for (entries) |*entry| {
        // 再実行時のリーク防止: 既存アロケーションを解放してリセット
        if (entry.process_name) |name| allocator.free(name);
        if (entry.cmdline) |cmd| allocator.free(cmd);
        entry.process_name = null;
        entry.cmdline = null;

        const pid = entry.pid orelse continue;

        entry.process_name = readCommFromPath(allocator, proc_path, pid) catch null;
        entry.cmdline = readCmdlineFromPath(allocator, proc_path, pid) catch null;
    }
}

/// buildInodePidMap で取得した pid を持つ各 PortEntry に process_name と cmdline を付与する。
/// 付与した文字列はすべて allocator で確保され、呼び出し元が管理する責任を持つ。
pub fn resolveProcessInfo(allocator: std.mem.Allocator, entries: []types.PortEntry) !void {
    return resolveProcessInfoFromPath(allocator, entries, "/proc");
}
