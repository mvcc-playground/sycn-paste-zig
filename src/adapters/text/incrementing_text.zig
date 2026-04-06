const std = @import("std");
const interfaces = @import("../../core/interfaces.zig");

pub const IncrementingTextSource = struct {
    buffer: [128]u8 = undefined,
    count: u64 = 0,

    pub fn init() IncrementingTextSource {
        return .{};
    }

    pub fn asAdapter(self: *IncrementingTextSource) interfaces.TextSourceAdapter {
        return .{
            .ctx = self,
            .get_text_fn = getText,
        };
    }

    fn getText(ctx: *anyopaque) ![]const u8 {
        const self: *IncrementingTextSource = @ptrCast(@alignCast(ctx));
        self.count += 1;
        return std.fmt.bufPrint(&self.buffer, "hello word from zig - cont: {d}", .{self.count});
    }
};

test "incrementing text source increments count on each call" {
    var source = IncrementingTextSource.init();
    const adapter = source.asAdapter();

    const first = try adapter.getText();
    try std.testing.expectEqualStrings("hello word from zig - cont: 1", first);

    const second = try adapter.getText();
    try std.testing.expectEqualStrings("hello word from zig - cont: 2", second);
}
