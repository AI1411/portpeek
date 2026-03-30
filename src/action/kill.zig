const std = @import("std");

pub fn killByPort(allocator: std.mem.Allocator, spec: []const u8, signal: []const u8) !void {
    _ = allocator;
    _ = spec;
    _ = signal;
}
