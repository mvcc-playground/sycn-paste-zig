const std = @import("std");
const app = @import("core/app.zig");
const websocket_adapter = @import("adapters/websocket/websocket_adapter.zig");
const websocket_text_source = @import("adapters/websocket/websocket_text_source.zig");
const websocket_state = @import("adapters/websocket/websocket_state.zig");
const paste_windows = @import("adapters/windows/paste_windows.zig");
const interfaces = @import("core/interfaces.zig");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    // Shared state between polling adapter and text source
    var ws_state = websocket_state.WebSocketState.init(allocator);
    defer ws_state.deinit();

    // HTTP polling adapter (replaces WindowsTickAdapter)
    var ws_adapter = websocket_adapter.WebSocketAdapter.init(allocator, &ws_state, .{});

    // State-backed text source (replaces IncrementingTextSource)
    var text_source = websocket_text_source.WebSocketTextSource.init(&ws_state);

    // Paste adapter remains the same
    var paste = paste_windows.WindowsPasteAdapter.init(allocator);

    const adapters = interfaces.AppAdapters{
        .tick = ws_adapter.asAdapter(),
        .text_source = text_source.asAdapter(),
        .paste = paste.asAdapter(),
    };

    std.debug.print("Polling http://127.0.0.1:8000/poll...\n", .{});
    try app.runApp(adapters);
}
