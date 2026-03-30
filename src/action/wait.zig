// src/action/wait.zig
// wait subcommand: poll until port is released or timeout expires.

const std = @import("std");
const types = @import("types");
const proc_net = @import("proc_net");
const port_filter = @import("port_filter");

pub fn waitForPort(allocator: std.mem.Allocator, spec: []const u8, timeout_sec: u64) !void {
    const filter = port_filter.PortFilter.parse(allocator, spec) catch {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Invalid port spec: {s}\n", .{spec}) catch "Invalid port spec\n";
        std.fs.File.stderr().writeAll(msg) catch {};
        std.process.exit(1);
    };

    const deadline_ms = std.time.milliTimestamp() + @as(i64, @intCast(timeout_sec * 1000));

    var entries: std.ArrayList(types.PortEntry) = .empty;

    while (std.time.milliTimestamp() < deadline_ms) {
        entries.clearRetainingCapacity();
        try proc_net.scanAll(allocator, &entries);

        var port_in_use = false;
        for (entries.items) |entry| {
            if (filter.matches(entry.local_port)) {
                port_in_use = true;
                break;
            }
        }

        if (!port_in_use) {
            std.process.exit(0);
        }

        std.time.sleep(200 * std.time.ns_per_ms);
    }

    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "Timeout: port {s} was not released within {d}s\n", .{ spec, timeout_sec }) catch "Timeout\n";
    std.fs.File.stderr().writeAll(msg) catch {};
    std.process.exit(1);
}
