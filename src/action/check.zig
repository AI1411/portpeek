// src/action/check.zig
// check subcommand: verify ports are available, exit 1 on conflict.

const std = @import("std");
const types = @import("types");
const proc_net = @import("proc_net");
const proc_fd = @import("proc_fd");
const proc_info = @import("proc_info");

pub fn checkPorts(allocator: std.mem.Allocator, specs: []const []const u8) !void {
    var entries: std.ArrayList(types.PortEntry) = .empty;
    try proc_net.scanAll(allocator, &entries);
    try proc_fd.resolvePids(allocator, entries.items);
    try proc_info.resolveProcessInfo(allocator, entries.items);

    var has_conflict = false;

    for (specs) |spec| {
        const port = std.fmt.parseInt(u16, spec, 10) catch {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Invalid port number: {s}\n", .{spec}) catch "Invalid port\n";
            std.fs.File.stderr().writeAll(msg) catch {};
            continue;
        };

        for (entries.items) |entry| {
            if (entry.local_port != port) continue;
            if (entry.state != .listen) continue;

            const pid = entry.pid orelse 0;
            const name = entry.process_name orelse "?";
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "CONFLICT port {d} -> PID {d} ({s})\n", .{ port, pid, name }) catch "CONFLICT\n";
            std.fs.File.stdout().writeAll(msg) catch {};
            has_conflict = true;
        }
    }

    if (has_conflict) {
        std.process.exit(1);
    }
}
