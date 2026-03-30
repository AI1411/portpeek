const std = @import("std");

pub fn waitForPort(allocator: std.mem.Allocator, spec: []const u8, timeout_sec: u64) !void {
    _ = allocator;
    _ = spec;
    _ = timeout_sec;
}
