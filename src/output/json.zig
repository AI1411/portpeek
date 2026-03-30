const std = @import("std");
const types = @import("types");

pub fn printJson(entries: []const types.PortEntry, writer: anytype) !void {
    _ = entries;
    _ = writer;
}
