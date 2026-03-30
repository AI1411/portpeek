const types = @import("types");

/// LISTEN 状態のエントリのみを通過させるフィルタ。
pub fn isListen(entry: types.PortEntry) bool {
    return entry.state == .listen;
}
