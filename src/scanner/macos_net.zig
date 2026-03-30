// src/scanner/macos_net.zig
// macOS 環境で lsof を使ってソケット情報を取得する。

const std = @import("std");
const types = @import("types");

/// lsof -i -n -P -F pcntPT を実行してソケット情報を取得する。
pub fn scanAll(allocator: std.mem.Allocator, entries: *std.ArrayList(types.PortEntry)) !void {
    var child = std.process.Child.init(
        &[_][]const u8{ "lsof", "-i", "-n", "-P", "-F", "pcntPT" },
        allocator,
    );
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();

    // 行単位で読み込んで出力全体を収集する
    var read_buf: [4096]u8 = undefined;
    var file_reader = child.stdout.?.reader(&read_buf);
    var output = std.ArrayList(u8).empty;
    while (try file_reader.interface.takeDelimiter('\n')) |line| {
        try output.appendSlice(allocator, line);
        try output.append(allocator, '\n');
    }
    _ = try child.wait();

    const stdout = try output.toOwnedSlice(allocator);
    try parseLsofOutput(allocator, stdout, entries);
}

/// lsof -F 形式の出力をパースして PortEntry に変換する。
/// 出力形式:
///   p<PID>           プロセス ID
///   c<COMMAND>       コマンド名
///   f<FD>            ファイルディスクリプタ（ソケットレコード開始）
///   t<TYPE>          IPv4 | IPv6
///   P<PROTO>         TCP | UDP
///   n<ADDR>          ローカル[->リモート] アドレス
///   TST=<STATE>      TCP 状態（T フィールドのうち ST= で始まるもの）
fn parseLsofOutput(allocator: std.mem.Allocator, data: []const u8, entries: *std.ArrayList(types.PortEntry)) !void {
    var pid: u32 = 0;
    var command: []const u8 = "";

    // FD レベルの状態
    var fd_type: []const u8 = "";
    var fd_proto: []const u8 = "";
    var fd_addr: []const u8 = "";
    var fd_state: []const u8 = "";
    var in_fd: bool = false;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const code = line[0];
        const val = line[1..];

        switch (code) {
            'p' => {
                if (in_fd) {
                    try emitEntry(allocator, pid, command, fd_type, fd_proto, fd_addr, fd_state, entries);
                    in_fd = false;
                }
                pid = std.fmt.parseInt(u32, val, 10) catch 0;
                command = "";
                fd_type = "";
                fd_proto = "";
                fd_addr = "";
                fd_state = "";
            },
            'c' => {
                command = try allocator.dupe(u8, val);
            },
            'f' => {
                if (in_fd) {
                    try emitEntry(allocator, pid, command, fd_type, fd_proto, fd_addr, fd_state, entries);
                }
                in_fd = true;
                fd_type = "";
                fd_proto = "";
                fd_addr = "";
                fd_state = "";
            },
            't' => {
                fd_type = val;
            },
            'P' => {
                fd_proto = val;
            },
            'n' => {
                fd_addr = val;
            },
            'T' => {
                // "TST=<STATE>" → code='T', val="ST=<STATE>"
                if (std.mem.startsWith(u8, val, "ST=")) {
                    fd_state = val[3..];
                }
            },
            else => {},
        }
    }

    if (in_fd) {
        try emitEntry(allocator, pid, command, fd_type, fd_proto, fd_addr, fd_state, entries);
    }
}

fn emitEntry(
    allocator: std.mem.Allocator,
    pid: u32,
    command: []const u8,
    fd_type: []const u8,
    fd_proto: []const u8,
    fd_addr: []const u8,
    fd_state: []const u8,
    entries: *std.ArrayList(types.PortEntry),
) !void {
    const is_ipv4 = std.mem.eql(u8, fd_type, "IPv4");
    const is_ipv6 = std.mem.eql(u8, fd_type, "IPv6");
    if (!is_ipv4 and !is_ipv6) return;

    const is_tcp = std.mem.startsWith(u8, fd_proto, "TCP");
    const is_udp = std.mem.startsWith(u8, fd_proto, "UDP");
    if (!is_tcp and !is_udp) return;

    // アドレス文字列を local / remote に分割
    const arrow = std.mem.indexOf(u8, fd_addr, "->");
    const local_str = if (arrow) |a| fd_addr[0..a] else fd_addr;
    const remote_str = if (arrow) |a| fd_addr[a + 2 ..] else "*:0";

    const local_port = parsePort(local_str) orelse return;
    if (local_port == 0) return;

    const remote_port = parsePort(remote_str) orelse 0;

    var local_addr = [4]u8{ 0, 0, 0, 0 };
    var local_addr6 = [_]u8{0} ** 16;
    var remote_addr = [4]u8{ 0, 0, 0, 0 };
    var remote_addr6 = [_]u8{0} ** 16;

    if (is_ipv4) {
        local_addr = parseIPv4(local_str);
        remote_addr = parseIPv4(remote_str);
    } else {
        local_addr6 = parseIPv6(local_str);
        remote_addr6 = parseIPv6(remote_str);
    }

    const protocol: types.Protocol = if (is_tcp and is_ipv6) .tcp6 else if (is_tcp) .tcp else if (is_ipv6) .udp6 else .udp;
    const state = parseState(fd_state);

    try entries.append(allocator, types.PortEntry{
        .protocol = protocol,
        .local_addr = local_addr,
        .local_addr6 = local_addr6,
        .local_port = local_port,
        .remote_addr = remote_addr,
        .remote_addr6 = remote_addr6,
        .remote_port = remote_port,
        .state = state,
        .inode = 0,
        .pid = if (pid > 0) pid else null,
        .process_name = if (command.len > 0) try allocator.dupe(u8, command) else null,
        .cmdline = null,
        .uid = 0,
        .is_ipv6 = is_ipv6,
    });
}

/// "addr:port" または "[ipv6]:port" からポート番号を取得する。
fn parsePort(addr: []const u8) ?u16 {
    if (addr.len > 0 and addr[0] == '[') {
        // IPv6: "[::1]:8080"
        const bracket = std.mem.indexOf(u8, addr, "]") orelse return null;
        if (bracket + 1 >= addr.len or addr[bracket + 1] != ':') return null;
        const port_str = addr[bracket + 2 ..];
        if (std.mem.eql(u8, port_str, "*")) return 0;
        return std.fmt.parseInt(u16, port_str, 10) catch null;
    }
    // IPv4 or wildcard: "1.2.3.4:8080" or "*:8080"
    const colon = std.mem.lastIndexOf(u8, addr, ":") orelse return null;
    const port_str = addr[colon + 1 ..];
    if (std.mem.eql(u8, port_str, "*")) return 0;
    return std.fmt.parseInt(u16, port_str, 10) catch null;
}

/// "1.2.3.4:port" または "*:port" から IPv4 アドレスを取得する。
fn parseIPv4(addr: []const u8) [4]u8 {
    const colon = std.mem.lastIndexOf(u8, addr, ":") orelse return [4]u8{ 0, 0, 0, 0 };
    const ip_str = addr[0..colon];
    if (std.mem.eql(u8, ip_str, "*")) return [4]u8{ 0, 0, 0, 0 };
    var result = [4]u8{ 0, 0, 0, 0 };
    var parts = std.mem.splitScalar(u8, ip_str, '.');
    var i: usize = 0;
    while (parts.next()) |part| : (i += 1) {
        if (i >= 4) break;
        result[i] = std.fmt.parseInt(u8, part, 10) catch 0;
    }
    return result;
}

/// "[::1]:port" または "*:port" から IPv6 アドレスを取得する。
fn parseIPv6(addr: []const u8) [16]u8 {
    var result = [_]u8{0} ** 16;
    if (addr.len == 0 or addr[0] != '[') return result;
    const bracket = std.mem.indexOf(u8, addr, "]") orelse return result;
    const ip_str = addr[1..bracket];
    const parsed = std.net.Address.parseIp6(ip_str, 0) catch return result;
    @memcpy(&result, &parsed.in6.sa.addr);
    return result;
}

fn parseState(s: []const u8) types.SocketState {
    if (std.mem.eql(u8, s, "LISTEN")) return .listen;
    if (std.mem.eql(u8, s, "ESTABLISHED")) return .established;
    if (std.mem.eql(u8, s, "SYN_SENT")) return .syn_sent;
    if (std.mem.eql(u8, s, "SYN_RCVD")) return .syn_recv;
    if (std.mem.eql(u8, s, "FIN_WAIT_1")) return .fin_wait1;
    if (std.mem.eql(u8, s, "FIN_WAIT_2")) return .fin_wait2;
    if (std.mem.eql(u8, s, "TIME_WAIT")) return .time_wait;
    if (std.mem.eql(u8, s, "CLOSE_WAIT")) return .close_wait;
    if (std.mem.eql(u8, s, "LAST_ACK")) return .last_ack;
    if (std.mem.eql(u8, s, "CLOSING")) return .closing;
    return .unknown;
}
