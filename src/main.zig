const std = @import("std");
const builtin = @import("builtin");
const types = @import("types");
const proc_net = @import("proc_net");
const proc_fd = @import("proc_fd");
const proc_info = @import("proc_info");
const table = @import("table");
const json_out = @import("json_out");
const port_filter = @import("port_filter");
const process_filter = @import("process_filter");
const state_filter = @import("state_filter");
const kill_action = @import("kill_action");
const wait_action = @import("wait_action");
const check_action = @import("check_action");
const tui = @import("tui");

const Subcommand = enum {
    list,
    kill,
    wait,
    check,
    watch,
};

pub fn main() !void {
    if (comptime builtin.os.tag != .linux) {
        var stderr_buf: [256]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
        try stderr_writer.interface.writeAll("portsnap: only supported on Linux\n");
        try stderr_writer.interface.flush();
        std.process.exit(1);
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    // オプション
    var listen_only = false;
    var use_json = false;
    var port_spec: ?[]const u8 = null;
    var process_pattern: ?[]const u8 = null;
    var subcommand: Subcommand = .list;
    var subcommand_port: ?[]const u8 = null;
    var kill_signal: []const u8 = "SIGTERM";
    var wait_timeout: u64 = 30;
    var check_ports = std.ArrayList([]const u8).init(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-l")) {
            listen_only = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            use_json = true;
        } else if (std.mem.eql(u8, arg, "-p")) {
            i += 1;
            if (i < args.len) process_pattern = args[i];
        } else if (std.mem.eql(u8, arg, "kill")) {
            subcommand = .kill;
            i += 1;
            if (i < args.len) subcommand_port = args[i];
        } else if (std.mem.eql(u8, arg, "wait")) {
            subcommand = .wait;
            i += 1;
            if (i < args.len) subcommand_port = args[i];
        } else if (std.mem.eql(u8, arg, "check")) {
            subcommand = .check;
            i += 1;
            while (i < args.len) : (i += 1) {
                try check_ports.append(args[i]);
            }
        } else if (std.mem.eql(u8, arg, "watch")) {
            subcommand = .watch;
        } else if (std.mem.eql(u8, arg, "--signal")) {
            i += 1;
            if (i < args.len) kill_signal = args[i];
        } else if (std.mem.eql(u8, arg, "--timeout")) {
            i += 1;
            if (i < args.len) {
                const t = args[i];
                const num_part = if (std.mem.endsWith(u8, t, "s")) t[0 .. t.len - 1] else t;
                wait_timeout = std.fmt.parseInt(u64, num_part, 10) catch 30;
            }
        } else if (std.mem.startsWith(u8, arg, ":")) {
            port_spec = arg;
        }
    }

    switch (subcommand) {
        .kill => {
            const spec = subcommand_port orelse {
                std.debug.print("Usage: portsnap kill :PORT\n", .{});
                std.process.exit(1);
            };
            try kill_action.killByPort(allocator, spec, kill_signal);
        },
        .wait => {
            const spec = subcommand_port orelse {
                std.debug.print("Usage: portsnap wait :PORT [--timeout 30s]\n", .{});
                std.process.exit(1);
            };
            try wait_action.waitForPort(allocator, spec, wait_timeout);
        },
        .check => {
            try check_action.checkPorts(allocator, check_ports.items);
        },
        .watch => {
            try tui.run(allocator);
        },
        .list => {
            var entries: std.ArrayList(types.PortEntry) = .empty;
            try proc_net.scanAll(allocator, &entries);
            try proc_fd.resolvePids(allocator, entries.items);
            try proc_info.resolveProcessInfo(allocator, entries.items);

            // フィルタ適用
            var filtered = std.ArrayList(types.PortEntry).init(allocator);
            for (entries.items) |e| {
                if (listen_only and !state_filter.isListen(e)) continue;
                if (port_spec) |spec| {
                    const f = port_filter.PortFilter.parse(allocator, spec) catch continue;
                    if (!f.matches(e.local_port)) continue;
                }
                if (process_pattern) |pat| {
                    var pf = try process_filter.ProcessFilter.init(allocator, pat);
                    defer pf.deinit();
                    if (!pf.matches(e.process_name)) continue;
                }
                try filtered.append(e);
            }

            var stdout_buf: [8192]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
            if (use_json) {
                try json_out.printJson(filtered.items, &stdout_writer.interface);
                try stdout_writer.interface.flush();
            } else {
                try table.printTable(filtered.items, &stdout_writer.interface);
                try stdout_writer.interface.flush();
            }
        },
    }
}
