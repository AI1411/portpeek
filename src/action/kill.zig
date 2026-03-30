// src/action/kill.zig
// kill subcommand: send signal to process using specified port.

const std = @import("std");
const types = @import("types");
const proc_net = @import("proc_net");
const proc_fd = @import("proc_fd");
const proc_info = @import("proc_info");
const port_filter = @import("port_filter");
const signal_utils = @import("signal");

pub fn killByPort(allocator: std.mem.Allocator, spec: []const u8, sig_name: []const u8) !void {
    const sig = signal_utils.Signal.fromString(sig_name) catch {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Unknown signal: {s}\n", .{sig_name}) catch "Unknown signal\n";
        std.fs.File.stderr().writeAll(msg) catch {};
        std.process.exit(1);
    };

    const filter = port_filter.PortFilter.parse(allocator, spec) catch {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Invalid port spec: {s}\n", .{spec}) catch "Invalid port spec\n";
        std.fs.File.stderr().writeAll(msg) catch {};
        std.process.exit(1);
    };

    var entries: std.ArrayList(types.PortEntry) = .empty;
    try proc_net.scanAll(allocator, &entries);
    try proc_fd.resolvePids(allocator, entries.items);
    try proc_info.resolveProcessInfo(allocator, entries.items);

    var found = false;
    for (entries.items) |entry| {
        if (!filter.matches(entry.local_port)) continue;
        const pid = entry.pid orelse continue;

        signal_utils.sendSignal(pid, sig) catch |err| {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Failed to send {s} to PID {d}: {}\n", .{ sig_name, pid, err }) catch "Failed to send signal\n";
            std.fs.File.stderr().writeAll(msg) catch {};
            continue;
        };

        const name = entry.process_name orelse "?";
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Sent {s} to PID {d} ({s}) on port {d}\n", .{ sig_name, pid, name, entry.local_port }) catch "Sent signal\n";
        std.fs.File.stderr().writeAll(msg) catch {};
        found = true;
    }

    if (!found) {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "No process found on port {s}\n", .{spec}) catch "No process found\n";
        std.fs.File.stderr().writeAll(msg) catch {};
        std.process.exit(1);
    }
}
