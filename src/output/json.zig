// src/output/json.zig
// JSON output for PortEntry list.

const std = @import("std");
const types = @import("types");

fn writeJsonString(writer: anytype, s: []const u8) !void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x00...0x08, 0x0B...0x0C, 0x0E...0x1F => {
                var buf: [7]u8 = undefined;
                const escaped = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}) catch unreachable;
                try writer.writeAll(escaped);
            },
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

pub fn printJson(entries: []const types.PortEntry, writer: anytype) !void {
    try writer.writeAll("[\n");
    for (entries, 0..) |entry, i| {
        var local_buf: [16]u8 = undefined;
        var remote_buf: [16]u8 = undefined;

        const local_addr_str = std.fmt.bufPrint(&local_buf, "{d}.{d}.{d}.{d}", .{
            entry.local_addr[0], entry.local_addr[1],
            entry.local_addr[2], entry.local_addr[3],
        }) catch "0.0.0.0";

        const remote_addr_str = std.fmt.bufPrint(&remote_buf, "{d}.{d}.{d}.{d}", .{
            entry.remote_addr[0], entry.remote_addr[1],
            entry.remote_addr[2], entry.remote_addr[3],
        }) catch "0.0.0.0";

        try writer.writeAll("  {\n");
        try writer.print("    \"protocol\": \"{s}\",\n", .{entry.protocol.toString()});
        try writer.print("    \"local_addr\": \"{s}\",\n", .{local_addr_str});
        try writer.print("    \"local_port\": {d},\n", .{entry.local_port});
        try writer.print("    \"remote_addr\": \"{s}\",\n", .{remote_addr_str});
        try writer.print("    \"remote_port\": {d},\n", .{entry.remote_port});
        try writer.print("    \"state\": \"{s}\",\n", .{entry.state.toString()});

        if (entry.pid) |pid| {
            try writer.print("    \"pid\": {d},\n", .{pid});
        } else {
            try writer.writeAll("    \"pid\": null,\n");
        }

        if (entry.process_name) |name| {
            try writer.writeAll("    \"process\": ");
            try writeJsonString(writer, name);
            try writer.writeAll(",\n");
        } else {
            try writer.writeAll("    \"process\": null,\n");
        }

        if (entry.cmdline) |cmd| {
            try writer.writeAll("    \"cmdline\": ");
            try writeJsonString(writer, cmd);
            try writer.writeAll(",\n");
        } else {
            try writer.writeAll("    \"cmdline\": null,\n");
        }

        try writer.print("    \"uid\": {d},\n", .{entry.uid});
        try writer.print("    \"inode\": {d}\n", .{entry.inode});

        if (i < entries.len - 1) {
            try writer.writeAll("  },\n");
        } else {
            try writer.writeAll("  }\n");
        }
    }
    try writer.writeAll("]\n");
}
