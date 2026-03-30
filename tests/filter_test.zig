const std = @import("std");
const process_filter = @import("process_filter");
const state_filter = @import("state_filter");
const types = @import("types");

// ── ProcessFilter ──────────────────────────────────────────────────────────

test "ProcessFilter: exact match" {
    const f = process_filter.ProcessFilter{ .pattern = "node" };
    try std.testing.expect(f.matches("node"));
}

test "ProcessFilter: no match" {
    const f = process_filter.ProcessFilter{ .pattern = "node" };
    try std.testing.expect(!f.matches("go"));
}

test "ProcessFilter: OR match – first token" {
    const f = process_filter.ProcessFilter{ .pattern = "go|rust|node" };
    try std.testing.expect(f.matches("go"));
}

test "ProcessFilter: OR match – middle token" {
    const f = process_filter.ProcessFilter{ .pattern = "go|rust|node" };
    try std.testing.expect(f.matches("rust"));
}

test "ProcessFilter: OR match – last token" {
    const f = process_filter.ProcessFilter{ .pattern = "go|rust|node" };
    try std.testing.expect(f.matches("node"));
}

test "ProcessFilter: OR match – no match" {
    const f = process_filter.ProcessFilter{ .pattern = "go|rust|node" };
    try std.testing.expect(!f.matches("python"));
}

test "ProcessFilter: null name returns false" {
    const f = process_filter.ProcessFilter{ .pattern = "node" };
    try std.testing.expect(!f.matches(null));
}

test "ProcessFilter: single pipe pattern" {
    const f = process_filter.ProcessFilter{ .pattern = "a|b" };
    try std.testing.expect(f.matches("a"));
    try std.testing.expect(f.matches("b"));
    try std.testing.expect(!f.matches("c"));
}

// ── isListen ──────────────────────────────────────────────────────────────

fn makeEntry(state: types.SocketState) types.PortEntry {
    return types.PortEntry{
        .protocol = .tcp,
        .local_addr = .{ 0, 0, 0, 0 },
        .local_addr6 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        .local_port = 8080,
        .remote_addr = .{ 0, 0, 0, 0 },
        .remote_addr6 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        .remote_port = 0,
        .state = state,
        .inode = 0,
        .pid = null,
        .process_name = null,
        .cmdline = null,
        .uid = 0,
        .is_ipv6 = false,
    };
}

test "isListen: LISTEN state returns true" {
    const entry = makeEntry(.listen);
    try std.testing.expect(state_filter.isListen(entry));
}

test "isListen: ESTABLISHED state returns false" {
    const entry = makeEntry(.established);
    try std.testing.expect(!state_filter.isListen(entry));
}

test "isListen: CLOSE_WAIT state returns false" {
    const entry = makeEntry(.close_wait);
    try std.testing.expect(!state_filter.isListen(entry));
}

test "isListen: TIME_WAIT state returns false" {
    const entry = makeEntry(.time_wait);
    try std.testing.expect(!state_filter.isListen(entry));
}

test "isListen: UNKNOWN state returns false" {
    const entry = makeEntry(.unknown);
    try std.testing.expect(!state_filter.isListen(entry));
}
