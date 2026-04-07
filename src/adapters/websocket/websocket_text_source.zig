const std = @import("std");
const interfaces = @import("../../core/interfaces.zig");
const WebSocketState = @import("websocket_state.zig").WebSocketState;

pub const WebSocketTextSource = struct {
    state: *WebSocketState,

    pub fn init(state: *WebSocketState) WebSocketTextSource {
        return .{
            .state = state,
        };
    }

    pub fn asAdapter(self: *WebSocketTextSource) interfaces.TextSourceAdapter {
        return .{
            .ctx = @ptrCast(self),
            .get_text_fn = getText,
        };
    }

    fn getText(ctx: *anyopaque) anyerror![]const u8 {
        const self: *WebSocketTextSource = @ptrCast(@alignCast(ctx));
        return self.state.getText() orelse "";
    }
};

test "WebSocketTextSource returns empty string when no text" {
    const allocator = std.testing.allocator;
    var state = WebSocketState.init(allocator);
    defer state.deinit();

    var source = WebSocketTextSource.init(&state);
    const adapter = source.asAdapter();

    const text = try adapter.getText();
    try std.testing.expectEqualStrings("", text);
}

test "WebSocketTextSource returns text from state" {
    const allocator = std.testing.allocator;
    var state = WebSocketState.init(allocator);
    defer state.deinit();

    try state.setText("Hello from WebSocket");

    var source = WebSocketTextSource.init(&state);
    const adapter = source.asAdapter();

    const text = try adapter.getText();
    try std.testing.expectEqualStrings("Hello from WebSocket", text);
}
