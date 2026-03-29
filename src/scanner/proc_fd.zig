// src/scanner/proc_fd.zig
// /proc/[pid]/fd/ のシンボリックリンクを走査して inode→PID の逆引き HashMap を構築する。

const std = @import("std");
const types = @import("types");

/// 指定した proc_path を走査して inode → PID の HashMap を構築する（テスト用）。
/// /proc/<pid>/fd/<fd> のシンボリックリンクが "socket:[inode]" のパターンに一致する場合、
/// inode を PID にマッピングする。
pub fn buildInodePidMapFromPath(allocator: std.mem.Allocator, proc_path: []const u8) !std.AutoHashMap(u64, u32) {
    var map = std.AutoHashMap(u64, u32).init(allocator);
    errdefer map.deinit();

    var proc_dir = std.fs.openDirAbsolute(proc_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return map;
        return err;
    };
    defer proc_dir.close();

    var proc_iter = proc_dir.iterate();
    while (try proc_iter.next()) |proc_entry| {
        if (proc_entry.kind != .directory) continue;

        // 数字名ディレクトリのみ処理 (PID)
        const pid = std.fmt.parseInt(u32, proc_entry.name, 10) catch continue;

        // <proc_path>/<pid>/fd を開く
        var fd_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const fd_path = std.fmt.bufPrint(&fd_path_buf, "{s}/{d}/fd", .{ proc_path, pid }) catch continue;

        var fd_dir = std.fs.openDirAbsolute(fd_path, .{ .iterate = true }) catch continue;
        defer fd_dir.close();

        var fd_iter = fd_dir.iterate();
        while (try fd_iter.next()) |fd_entry| {
            if (fd_entry.kind != .sym_link) continue;

            // シンボリックリンクのターゲットを読む
            var link_buf: [256]u8 = undefined;
            const link_target = fd_dir.readLink(fd_entry.name, &link_buf) catch continue;

            // "socket:[inode]" パターンのマッチ
            const prefix = "socket:[";
            if (!std.mem.startsWith(u8, link_target, prefix)) continue;
            if (link_target[link_target.len - 1] != ']') continue;

            const inode_str = link_target[prefix.len .. link_target.len - 1];
            const inode = std.fmt.parseInt(u64, inode_str, 10) catch continue;

            // 既にエントリがある場合はスキップ (先勝ち)
            if (!map.contains(inode)) {
                try map.put(inode, pid);
            }
        }
    }

    return map;
}

/// /proc を走査して inode → PID の HashMap を構築する。
pub fn buildInodePidMap(allocator: std.mem.Allocator) !std.AutoHashMap(u64, u32) {
    return buildInodePidMapFromPath(allocator, "/proc");
}

/// buildInodePidMap で取得したマップを使い、各 PortEntry に pid を付与する。
pub fn resolvePids(allocator: std.mem.Allocator, entries: []types.PortEntry) !void {
    var map = try buildInodePidMap(allocator);
    defer map.deinit();

    for (entries) |*entry| {
        if (map.get(entry.inode)) |pid| {
            entry.pid = pid;
        }
    }
}
