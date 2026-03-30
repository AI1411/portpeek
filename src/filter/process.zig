const std = @import("std");

pub const ProcessFilter = struct {
    pattern: []const u8,

    /// "|" 区切りで OR マッチ。name が null の場合は false を返す。
    pub fn matches(self: ProcessFilter, name: ?[]const u8) bool {
        const n = name orelse return false;
        var it = std.mem.splitScalar(u8, self.pattern, '|');
        while (it.next()) |part| {
            if (std.mem.eql(u8, part, n)) return true;
        }
        return false;
    }
};
