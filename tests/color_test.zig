// tests/color_test.zig
const std = @import("std");
const color = @import("color");
const types = @import("types");

test "colorForState: listen returns green" {
    try std.testing.expectEqualStrings(color.green, color.colorForState(.listen));
}

test "colorForState: established returns blue" {
    try std.testing.expectEqualStrings(color.blue, color.colorForState(.established));
}

test "colorForState: time_wait returns gray" {
    try std.testing.expectEqualStrings(color.gray, color.colorForState(.time_wait));
}

test "colorForState: close_wait returns yellow" {
    try std.testing.expectEqualStrings(color.yellow, color.colorForState(.close_wait));
}

test "colorForState: other states return white" {
    try std.testing.expectEqualStrings(color.white, color.colorForState(.syn_sent));
    try std.testing.expectEqualStrings(color.white, color.colorForState(.fin_wait1));
    try std.testing.expectEqualStrings(color.white, color.colorForState(.unknown));
}
