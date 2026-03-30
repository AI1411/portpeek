// src/utils/signal.zig
// POSIX signal definitions and sending utilities.

const std = @import("std");

pub const Signal = enum(u6) {
    SIGHUP = 1,
    SIGINT = 2,
    SIGKILL = 9,
    SIGTERM = 15,

    pub fn fromString(s: []const u8) !Signal {
        if (std.mem.eql(u8, s, "SIGHUP") or std.mem.eql(u8, s, "1")) return .SIGHUP;
        if (std.mem.eql(u8, s, "SIGINT") or std.mem.eql(u8, s, "2")) return .SIGINT;
        if (std.mem.eql(u8, s, "SIGKILL") or std.mem.eql(u8, s, "9")) return .SIGKILL;
        if (std.mem.eql(u8, s, "SIGTERM") or std.mem.eql(u8, s, "15")) return .SIGTERM;
        return error.UnknownSignal;
    }
};

pub fn sendSignal(pid: u32, sig: Signal) !void {
    const pid_signed: std.posix.pid_t = @intCast(pid);
    try std.posix.kill(pid_signed, @as(u8, @intFromEnum(sig)));
}
