const interfaces = @import("../../core/interfaces.zig");

pub const FixedTextSource = struct {
    text: []const u8,

    pub fn init(text: []const u8) FixedTextSource {
        return .{ .text = text };
    }

    pub fn asAdapter(self: *FixedTextSource) interfaces.TextSourceAdapter {
        return .{
            .ctx = self,
            .get_text_fn = getText,
        };
    }

    fn getText(ctx: *anyopaque) ![]const u8 {
        const self: *FixedTextSource = @ptrCast(@alignCast(ctx));
        return self.text;
    }
};

test "fixed text source returns configured text" {
    var source = FixedTextSource.init("Hello world from zig");
    const adapter = source.asAdapter();
    const text = try adapter.getText();
    try std.testing.expectEqualStrings("Hello world from zig", text);
}

const std = @import("std");
