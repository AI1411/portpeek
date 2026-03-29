const std = @import("std");
const hex = @import("hex");

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

test "decodeIpv6: invalid length returns error" {
    try std.testing.expectError(error.InvalidLength, hex.decodeIpv6("0000000000000000000000000000000"));
    try std.testing.expectError(error.InvalidLength, hex.decodeIpv6("000000000000000000000000000000000"));
}
