const std = @import("std");

pub const PortFilter = union(enum) {
    single: u16,
    range: struct { min: u16, max: u16 },

    pub fn parse(allocator: std.mem.Allocator, spec: []const u8) !PortFilter {
        _ = allocator;
        if (spec.len == 0 or spec[0] != ':') return error.InvalidSpec;
        const port_part = spec[1..];
        if (std.mem.indexOf(u8, port_part, "-")) |dash_idx| {
            const min = try std.fmt.parseInt(u16, port_part[0..dash_idx], 10);
            const max = try std.fmt.parseInt(u16, port_part[dash_idx + 1 ..], 10);
            if (min > max) return error.InvalidSpec;
            return .{ .range = .{ .min = min, .max = max } };
        } else {
            const port = try std.fmt.parseInt(u16, port_part, 10);
            return .{ .single = port };
        }
    }

    pub fn matches(self: PortFilter, port: u16) bool {
        return switch (self) {
            .single => |p| p == port,
            .range => |r| port >= r.min and port <= r.max,
        };
    }
};
