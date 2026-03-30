// src/output/tui.zig
// watch サブコマンド: 1 秒間隔でポート使用状況をリフレッシュする TUI。

const std = @import("std");
const types = @import("types");
const proc_net = @import("proc_net");
const proc_fd = @import("proc_fd");
const proc_info = @import("proc_info");
const state_filter = @import("state_filter");

const col_port: usize = 6;
const col_proto: usize = 6;
const col_process: usize = 14;
const col_pid: usize = 7;
const sep_len: usize = 49;

fn writeCol(writer: anytype, s: []const u8, width: usize) !void {
    const actual = if (s.len > width) s[0..width] else s;
    try writer.writeAll(actual);
    if (actual.len < width) {
        var i: usize = actual.len;
        while (i < width) : (i += 1) try writer.writeByte(' ');
    }
}

fn writeSep(writer: anytype) !void {
    var i: usize = 0;
    while (i < sep_len) : (i += 1) try writer.writeAll("\u{2500}");
    try writer.writeByte('\n');
}

pub fn run(allocator: std.mem.Allocator) !void {
    var out_buf: [16384]u8 = undefined;
    var out_writer = std.fs.File.stdout().writer(&out_buf);
    const w = &out_writer.interface;

    var entries: std.ArrayList(types.PortEntry) = .empty;
    var listen_entries: std.ArrayList(types.PortEntry) = .empty;

    while (true) {
        entries.clearRetainingCapacity();
        listen_entries.clearRetainingCapacity();

        try proc_net.scanAll(allocator, &entries);
        try proc_fd.resolvePids(allocator, entries.items);
        try proc_info.resolveProcessInfo(allocator, entries.items);

        for (entries.items) |e| {
            if (state_filter.isListen(e)) try listen_entries.append(allocator, e);
        }

        // スクリーンクリア
        try w.writeAll("\x1b[2J\x1b[H");

        // ヘッダー
        try w.print("portsnap watch \u{2014} {d} ports listening  Refresh: 1.0s\n", .{listen_entries.items.len});

        // セパレーター
        try writeSep(w);

        // カラムヘッダー
        try w.writeByte(' ');
        try writeCol(w, "PORT", col_port);
        try writeCol(w, "PROTO", col_proto);
        try writeCol(w, "PROCESS", col_process);
        try writeCol(w, "PID", col_pid);
        try w.writeAll("STATE\n");

        // セパレーター
        try writeSep(w);

        // 各エントリー
        var port_buf: [12]u8 = undefined;
        var pid_buf: [12]u8 = undefined;
        for (listen_entries.items) |e| {
            const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{e.local_port}) catch "?";
            const proto_str = e.protocol.toString();
            const process_str = e.process_name orelse "-";
            const pid_str: []const u8 = if (e.pid) |p|
                std.fmt.bufPrint(&pid_buf, "{d}", .{p}) catch "-"
            else
                "-";
            const state_str = e.state.toString();

            try w.writeByte(' ');
            try writeCol(w, port_str, col_port);
            try writeCol(w, proto_str, col_proto);
            try writeCol(w, process_str, col_process);
            try writeCol(w, pid_str, col_pid);
            try w.writeAll(state_str);
            try w.writeByte('\n');
        }

        try w.writeByte('\n');
        try w.writeAll("[Ctrl+C] \u{7d42}\u{4e86}\n");
        try out_writer.interface.flush();

        std.Thread.sleep(std.time.ns_per_s);
    }
}
