// src/utils/color.zig
// ANSI escape color code helpers for terminal output.

const types = @import("../scanner/types.zig");
const SocketState = types.SocketState;

// Reset and style codes
pub const reset = "\x1b[0m";
pub const bold = "\x1b[1m";
pub const dim = "\x1b[2m";

// Color codes
pub const green = "\x1b[32m";
pub const blue = "\x1b[34m";
pub const yellow = "\x1b[33m";
pub const gray = "\x1b[90m";
pub const red = "\x1b[31m";
pub const cyan = "\x1b[36m";
pub const white = "\x1b[37m";

/// Return the ANSI color code corresponding to the given SocketState.
/// - LISTEN      → green
/// - ESTABLISHED → blue
/// - TIME_WAIT   → gray
/// - CLOSE_WAIT  → yellow (leak candidate)
/// - others      → white
pub fn colorForState(state: SocketState) []const u8 {
    return switch (state) {
        .listen => green,
        .established => blue,
        .time_wait => gray,
        .close_wait => yellow,
        else => white,
    };
}
