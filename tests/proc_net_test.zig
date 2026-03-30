const std = @import("std");
const hex = @import("hex");
const proc_net = @import("proc_net");
const port_filter = @import("port_filter");

// --- parseHexU8 ---

test "parseHexU8: valid hex chars lowercase" {
    try std.testing.expectEqual(@as(u8, 0x00), try hex.parseHexU8('0', '0'));
    try std.testing.expectEqual(@as(u8, 0xFF), try hex.parseHexU8('f', 'f'));
    try std.testing.expectEqual(@as(u8, 0xAB), try hex.parseHexU8('a', 'b'));
    try std.testing.expectEqual(@as(u8, 0x7F), try hex.parseHexU8('7', 'f'));
}

test "parseHexU8: valid hex chars uppercase" {
    try std.testing.expectEqual(@as(u8, 0xFF), try hex.parseHexU8('F', 'F'));
    try std.testing.expectEqual(@as(u8, 0xAB), try hex.parseHexU8('A', 'B'));
}

test "parseHexU8: invalid char returns error" {
    try std.testing.expectError(error.InvalidHexChar, hex.parseHexU8('g', '0'));
    try std.testing.expectError(error.InvalidHexChar, hex.parseHexU8('0', 'z'));
    try std.testing.expectError(error.InvalidHexChar, hex.parseHexU8(' ', '0'));
}

// --- decodeIpv4 ---

test "decodeIpv4: 00000000 -> 0.0.0.0" {
    const result = try hex.decodeIpv4("00000000");
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0, 0 }, &result);
}

test "decodeIpv4: 0100007F -> 127.0.0.1 (little endian)" {
    const result = try hex.decodeIpv4("0100007F");
    try std.testing.expectEqualSlices(u8, &[_]u8{ 127, 0, 0, 1 }, &result);
}

test "decodeIpv4: 050011AC -> 172.17.0.5" {
    const result = try hex.decodeIpv4("050011AC");
    try std.testing.expectEqualSlices(u8, &[_]u8{ 172, 17, 0, 5 }, &result);
}

test "decodeIpv4: invalid length returns error" {
    try std.testing.expectError(error.InvalidLength, hex.decodeIpv4("0000000"));
    try std.testing.expectError(error.InvalidLength, hex.decodeIpv4("000000000"));
}

// --- decodePort ---

test "decodePort: 1F90 -> 8080" {
    const result = try hex.decodePort("1F90");
    try std.testing.expectEqual(@as(u16, 8080), result);
}

test "decodePort: 0035 -> 53" {
    const result = try hex.decodePort("0035");
    try std.testing.expectEqual(@as(u16, 53), result);
}

test "decodePort: 0000 -> 0" {
    const result = try hex.decodePort("0000");
    try std.testing.expectEqual(@as(u16, 0), result);
}

test "decodePort: CF5A -> 53082" {
    const result = try hex.decodePort("CF5A");
    try std.testing.expectEqual(@as(u16, 0xCF5A), result);
}

test "decodePort: invalid length returns error" {
    try std.testing.expectError(error.InvalidLength, hex.decodePort("1F9"));
    try std.testing.expectError(error.InvalidLength, hex.decodePort("1F900"));
}

// --- decodeIpv6 ---

test "decodeIpv6: all zeros -> [16]u8 zeros" {
    const result = try hex.decodeIpv6("00000000000000000000000000000000");
    try std.testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &result);
}

test "decodeIpv6: loopback 00000000000000000000000001000000 -> ::1" {
    // ::1 in /proc/net/tcp6 little-endian per 4-byte group: 00000000 00000000 00000000 01000000
    const result = try hex.decodeIpv6("00000000000000000000000001000000");
    const expected = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 };
    try std.testing.expectEqualSlices(u8, &expected, &result);
}

test "decodeIpv6: 2001:db8:1234:5678:9abc:def0:1111:2222 (multi-group, little-endian path)" {
    // 2001:0db8:1234:5678:9abc:def0:1111:2222
    // Network byte order (16 bytes):
    //   20 01 0d b8 | 12 34 56 78 | 9a bc de f0 | 11 11 22 22
    // /proc/net/tcp6 on little-endian (each 32-bit group reversed):
    //   B80D0120     78563412      F0DEBC9A      22221111
    const builtin = @import("builtin");
    if (builtin.cpu.arch.endian() != .little) return; // little-endian path only
    const result = try hex.decodeIpv6("B80D012078563412F0DEBC9A22221111");
    const expected = [_]u8{
        0x20, 0x01, 0x0d, 0xb8,
        0x12, 0x34, 0x56, 0x78,
        0x9a, 0xbc, 0xde, 0xf0,
        0x11, 0x11, 0x22, 0x22,
    };
    try std.testing.expectEqualSlices(u8, &expected, &result);
}

test "decodeIpv6: invalid length returns error" {
    try std.testing.expectError(error.InvalidLength, hex.decodeIpv6("0000000000000000000000000000000"));
    try std.testing.expectError(error.InvalidLength, hex.decodeIpv6("000000000000000000000000000000000"));
}

// --- parseTcpLine ---

test "parseTcpLine: LISTEN エントリ" {
    const allocator = std.testing.allocator;
    // tcp_sample.txt の1行目: port=8080, state=LISTEN, inode=12345
    const line = "   0: 00000000:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 12345 1 0000000000000000 100 0 0 10 0";
    const entry = proc_net.parseTcpLine(allocator, line, .tcp) orelse {
        return error.ExpectedEntry;
    };
    try std.testing.expectEqual(@as(u16, 8080), entry.local_port);
    try std.testing.expectEqual(.listen, entry.state);
    try std.testing.expectEqual(@as(u64, 12345), entry.inode);
    try std.testing.expectEqual(false, entry.is_ipv6);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0, 0 }, &entry.local_addr);
}

test "parseTcpLine: ESTABLISHED エントリ" {
    const allocator = std.testing.allocator;
    // tcp_sample.txt の3行目: 172.17.0.5:8080 -> 172.17.0.3:53082, ESTABLISHED, inode=34567
    const line = "   2: 050011AC:1F90 030011AC:CF5A 01 00000000:00000000 00:00000000 00000000  1000        0 34567 1 0000000000000000 20 4 24 10 -1";
    const entry = proc_net.parseTcpLine(allocator, line, .tcp) orelse {
        return error.ExpectedEntry;
    };
    try std.testing.expectEqual(@as(u16, 8080), entry.local_port);
    try std.testing.expectEqual(.established, entry.state);
    try std.testing.expectEqual(@as(u64, 34567), entry.inode);
    try std.testing.expectEqual(false, entry.is_ipv6);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 172, 17, 0, 5 }, &entry.local_addr);
    try std.testing.expectEqual(@as(u16, 0xCF5A), entry.remote_port);
}

test "parseTcpLine: ヘッダー行は null を返す" {
    const allocator = std.testing.allocator;
    const header = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode";
    const result = proc_net.parseTcpLine(allocator, header, .tcp);
    try std.testing.expectEqual(@as(?@import("types").PortEntry, null), result);
}

test "scanFile: fixtures/tcp_sample.txt を読み込んで 3 エントリ返す" {
    const allocator = std.testing.allocator;
    var entries: std.ArrayList(@import("types").PortEntry) = .empty;
    defer entries.deinit(allocator);

    try proc_net.scanFile(allocator, "tests/fixtures/tcp_sample.txt", .tcp, &entries);
    try std.testing.expectEqual(@as(usize, 3), entries.items.len);
    try std.testing.expectEqual(@as(u16, 8080), entries.items[0].local_port);
    try std.testing.expectEqual(.listen, entries.items[0].state);
    try std.testing.expectEqual(@as(u64, 12345), entries.items[0].inode);
}

test "scanFile: fixtures/tcp6_sample.txt を読み込んで 1 エントリ返す" {
    const allocator = std.testing.allocator;
    var entries: std.ArrayList(@import("types").PortEntry) = .empty;
    defer entries.deinit(allocator);

    try proc_net.scanFile(allocator, "tests/fixtures/tcp6_sample.txt", .tcp6, &entries);
    try std.testing.expectEqual(@as(usize, 1), entries.items.len);
    try std.testing.expect(entries.items[0].is_ipv6);
    try std.testing.expectEqual(@as(u16, 8081), entries.items[0].local_port); // 0x1F91
    try std.testing.expectEqual(.listen, entries.items[0].state);
    try std.testing.expectEqual(@as(u64, 45678), entries.items[0].inode);
    // ::1 のローカルアドレスを検証
    const expected_addr6 = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 };
    try std.testing.expectEqualSlices(u8, &expected_addr6, &entries.items[0].local_addr6);
}

// --- PortFilter ---

test "PortFilter: 単一ポートマッチ" {
    const f = try port_filter.PortFilter.parse(std.testing.allocator, ":8080");
    try std.testing.expect(f.matches(8080));
    try std.testing.expect(!f.matches(3000));
}

test "PortFilter: 範囲マッチ" {
    const f = try port_filter.PortFilter.parse(std.testing.allocator, ":3000-9000");
    try std.testing.expect(f.matches(5000));
    try std.testing.expect(!f.matches(2999));
}

test "PortFilter: 範囲境界値マッチ" {
    const f = try port_filter.PortFilter.parse(std.testing.allocator, ":3000-9000");
    try std.testing.expect(f.matches(3000));
    try std.testing.expect(f.matches(9000));
    try std.testing.expect(!f.matches(9001));
}

test "PortFilter: 逆順範囲はエラー" {
    try std.testing.expectError(error.InvalidSpec, port_filter.PortFilter.parse(std.testing.allocator, ":9000-3000"));
}

test "PortFilter: u16範囲外はエラー" {
    try std.testing.expectError(error.Overflow, port_filter.PortFilter.parse(std.testing.allocator, ":70000"));
}
