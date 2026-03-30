// src/scanner/docker.zig
// Docker unix ソケット経由でコンテナのポートマッピングを取得する。

const std = @import("std");

pub const DockerPort = struct {
    container_id: []const u8,
    container_name: []const u8,
    host_port: u16,
    container_port: u16,
    protocol: []const u8,
};

const sock_path = "/var/run/docker.sock";

/// Docker unix ソケットからコンテナのポートマッピングを取得する。
/// ソケットが存在しない場合は空スライスを返す（graceful degradation）。
pub fn fetchDockerPorts(allocator: std.mem.Allocator) ![]DockerPort {
    // ソケットが存在しない場合は空リストを返す
    std.fs.accessAbsolute(sock_path, .{}) catch {
        return try allocator.alloc(DockerPort, 0);
    };

    const addr = std.net.Address.initUnix(sock_path) catch {
        return try allocator.alloc(DockerPort, 0);
    };

    const sock = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
    defer std.posix.close(sock);

    std.posix.connect(sock, &addr.any, addr.getOsSockLen()) catch {
        return try allocator.alloc(DockerPort, 0);
    };

    // HTTP リクエスト送信
    const request = "GET /containers/json HTTP/1.0\r\nHost: localhost\r\n\r\n";
    _ = try std.posix.write(sock, request);

    // レスポンス受信
    var response: std.ArrayList(u8) = .empty;
    defer response.deinit(allocator);

    var buf: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(sock, &buf) catch break;
        if (n == 0) break;
        try response.appendSlice(allocator, buf[0..n]);
    }

    // HTTP ヘッダーをスキップして JSON ボディを取得
    const header_end = std.mem.indexOf(u8, response.items, "\r\n\r\n") orelse
        return try allocator.alloc(DockerPort, 0);
    const body = response.items[header_end + 4 ..];

    // JSON パース
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return try allocator.alloc(DockerPort, 0);
    defer parsed.deinit();

    const containers = switch (parsed.value) {
        .array => |arr| arr,
        else => return try allocator.alloc(DockerPort, 0),
    };

    var ports: std.ArrayList(DockerPort) = .empty;

    for (containers.items) |container| {
        const obj = switch (container) {
            .object => |o| o,
            else => continue,
        };

        const id_val = obj.get("Id") orelse continue;
        const id_full = switch (id_val) {
            .string => |s| s,
            else => continue,
        };
        // ID は先頭 12 文字に短縮
        const id = try allocator.dupe(u8, id_full[0..@min(id_full.len, 12)]);

        const names_val = obj.get("Names") orelse continue;
        const names_arr = switch (names_val) {
            .array => |a| a,
            else => continue,
        };
        const name = if (names_arr.items.len > 0) blk: {
            const n = switch (names_arr.items[0]) {
                .string => |s| s,
                else => break :blk try allocator.dupe(u8, ""),
            };
            // 先頭の "/" を除去
            const trimmed = if (n.len > 0 and n[0] == '/') n[1..] else n;
            break :blk try allocator.dupe(u8, trimmed);
        } else try allocator.dupe(u8, "");

        const ports_val = obj.get("Ports") orelse continue;
        const port_arr = switch (ports_val) {
            .array => |a| a,
            else => continue,
        };

        for (port_arr.items) |port_item| {
            const port_obj = switch (port_item) {
                .object => |o| o,
                else => continue,
            };

            const public_val = port_obj.get("PublicPort") orelse continue;
            const host_port: u16 = switch (public_val) {
                .integer => |n| @intCast(n),
                else => continue,
            };

            const private_val = port_obj.get("PrivatePort") orelse continue;
            const container_port: u16 = switch (private_val) {
                .integer => |n| @intCast(n),
                else => continue,
            };

            const type_val = port_obj.get("Type") orelse continue;
            const proto = switch (type_val) {
                .string => |s| try allocator.dupe(u8, s),
                else => continue,
            };

            try ports.append(allocator, .{
                .container_id = id,
                .container_name = name,
                .host_port = host_port,
                .container_port = container_port,
                .protocol = proto,
            });
        }
    }

    return try ports.toOwnedSlice(allocator);
}
