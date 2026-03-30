// src/scanner/proc_net.zig
// /proc/net/tcp, tcp6, udp, udp6 のパーサー（Linux）
// macOS では macos_net モジュールへ委譲する。

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types");
const hex_utils = @import("hex");
const macos_net = @import("macos_net");

/// /proc/net/tcp(6)/udp(6) の1行をパースして PortEntry を返す。
/// ヘッダー行・空行・パースエラーの場合は null を返す。
pub fn parseTcpLine(allocator: std.mem.Allocator, line: []const u8, protocol: types.Protocol) ?types.PortEntry {
    _ = allocator;

    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return null;

    // フィールドを空白で分割
    var fields: [12][]const u8 = undefined;
    var field_count: usize = 0;
    var iter = std.mem.tokenizeAny(u8, trimmed, " \t");
    while (iter.next()) |field| {
        if (field_count >= fields.len) break;
        fields[field_count] = field;
        field_count += 1;
    }

    if (field_count < 10) return null;

    // ヘッダー行の検出 (field[0] == "sl")
    if (std.mem.eql(u8, fields[0], "sl")) return null;

    // field[0] = "N:" (行番号)
    // field[1] = "XXXXXXXX:XXXX" (local_addr:port)
    // field[2] = "XXXXXXXX:XXXX" (remote_addr:port)
    // field[3] = "XX" (state hex)
    // field[4] = "XXXXXXXX:XXXXXXXX" (tx_queue:rx_queue)
    // field[5] = "XX:XXXXXXXX" (tr:tm->when)
    // field[6] = "XXXXXXXX" (retrnsmt)
    // field[7] = "NNNN" (uid)
    // field[8] = "N" (timeout)
    // field[9] = "NNNN" (inode)

    // local_address をパース
    const local_sep = std.mem.indexOfScalar(u8, fields[1], ':') orelse return null;
    const local_ip_hex = fields[1][0..local_sep];
    const local_port_hex = fields[1][local_sep + 1 ..];

    // remote_address をパース
    const remote_sep = std.mem.indexOfScalar(u8, fields[2], ':') orelse return null;
    const remote_ip_hex = fields[2][0..remote_sep];
    const remote_port_hex = fields[2][remote_sep + 1 ..];

    const is_ipv6 = protocol == .tcp6 or protocol == .udp6;

    // state をパース (hex u8)
    const state_val = std.fmt.parseInt(u8, fields[3], 16) catch return null;
    const state = types.SocketState.fromHex(state_val);

    // uid をパース
    const uid = std.fmt.parseInt(u32, std.mem.trim(u8, fields[7], " "), 10) catch return null;

    // inode をパース
    const inode = std.fmt.parseInt(u64, fields[9], 10) catch return null;

    // アドレスをデコード
    var local_addr: [4]u8 = .{ 0, 0, 0, 0 };
    var local_addr6: [16]u8 = .{0} ** 16;
    var remote_addr: [4]u8 = .{ 0, 0, 0, 0 };
    var remote_addr6: [16]u8 = .{0} ** 16;

    if (is_ipv6) {
        local_addr6 = hex_utils.decodeIpv6(local_ip_hex) catch return null;
        remote_addr6 = hex_utils.decodeIpv6(remote_ip_hex) catch return null;
    } else {
        local_addr = hex_utils.decodeIpv4(local_ip_hex) catch return null;
        remote_addr = hex_utils.decodeIpv4(remote_ip_hex) catch return null;
    }

    const local_port = hex_utils.decodePort(local_port_hex) catch return null;
    const remote_port = hex_utils.decodePort(remote_port_hex) catch return null;

    return types.PortEntry{
        .protocol = protocol,
        .local_addr = local_addr,
        .local_addr6 = local_addr6,
        .local_port = local_port,
        .remote_addr = remote_addr,
        .remote_addr6 = remote_addr6,
        .remote_port = remote_port,
        .state = state,
        .inode = inode,
        .pid = null,
        .process_name = null,
        .cmdline = null,
        .uid = uid,
        .is_ipv6 = is_ipv6,
    };
}

/// ファイルを1行ずつ読み込み、パースした PortEntry を entries に追記する。
pub fn scanFile(allocator: std.mem.Allocator, path: []const u8, protocol: types.Protocol, entries: *std.ArrayList(types.PortEntry)) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(&read_buf);

    while (try file_reader.interface.takeDelimiter('\n')) |line| {
        if (parseTcpLine(allocator, line, protocol)) |entry| {
            try entries.append(allocator, entry);
        }
    }
}

/// /proc/net/tcp, tcp6, udp, udp6 をすべてスキャンして entries に追記する（Linux）。
/// macOS では lsof を使用する。
pub fn scanAll(allocator: std.mem.Allocator, entries: *std.ArrayList(types.PortEntry)) !void {
    if (comptime builtin.os.tag == .macos) {
        return macos_net.scanAll(allocator, entries);
    }

    const targets = [_]struct { path: []const u8, protocol: types.Protocol }{
        .{ .path = "/proc/net/tcp", .protocol = .tcp },
        .{ .path = "/proc/net/tcp6", .protocol = .tcp6 },
        .{ .path = "/proc/net/udp", .protocol = .udp },
        .{ .path = "/proc/net/udp6", .protocol = .udp6 },
    };

    for (targets) |t| {
        scanFile(allocator, t.path, t.protocol, entries) catch |err| {
            if (err == error.FileNotFound) continue;
            return err;
        };
    }
}
