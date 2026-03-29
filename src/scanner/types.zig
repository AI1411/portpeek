// src/scanner/types.zig
const std = @import("std");

pub const Protocol = enum {
    tcp,
    tcp6,
    udp,
    udp6,

    pub fn toString(self: Protocol) []const u8 {
        return switch (self) {
            .tcp => "tcp",
            .tcp6 => "tcp6",
            .udp => "udp",
            .udp6 => "udp6",
        };
    }
};

pub const SocketState = enum(u8) {
    established = 0x01,
    syn_sent = 0x02,
    syn_recv = 0x03,
    fin_wait1 = 0x04,
    fin_wait2 = 0x05,
    time_wait = 0x06,
    close = 0x07,
    close_wait = 0x08,
    last_ack = 0x09,
    listen = 0x0A,
    closing = 0x0B,
    unknown = 0xFF,

    pub fn fromHex(val: u8) SocketState {
        return switch (val) {
            0x01 => .established,
            0x02 => .syn_sent,
            0x03 => .syn_recv,
            0x04 => .fin_wait1,
            0x05 => .fin_wait2,
            0x06 => .time_wait,
            0x07 => .close,
            0x08 => .close_wait,
            0x09 => .last_ack,
            0x0A => .listen,
            0x0B => .closing,
            else => .unknown,
        };
    }

    pub fn toString(self: SocketState) []const u8 {
        return switch (self) {
            .established => "ESTABLISHED",
            .syn_sent => "SYN_SENT",
            .syn_recv => "SYN_RECV",
            .fin_wait1 => "FIN_WAIT1",
            .fin_wait2 => "FIN_WAIT2",
            .time_wait => "TIME_WAIT",
            .close => "CLOSE",
            .close_wait => "CLOSE_WAIT",
            .last_ack => "LAST_ACK",
            .listen => "LISTEN",
            .closing => "CLOSING",
            .unknown => "UNKNOWN",
        };
    }
};

pub const PortEntry = struct {
    protocol: Protocol,
    local_addr: [4]u8, // IPv4。IPv6 は local_addr6 を使う
    local_addr6: [16]u8,
    local_port: u16,
    remote_addr: [4]u8,
    remote_addr6: [16]u8,
    remote_port: u16,
    state: SocketState,
    inode: u64,
    pid: ?u32,
    process_name: ?[]const u8, // /proc/[pid]/comm (最大16文字)
    cmdline: ?[]const u8, // /proc/[pid]/cmdline
    uid: u32,
    is_ipv6: bool,
};
