const std = @import("std");
const builtin = @import("builtin");
const app = @import("core/app.zig");
const interfaces = @import("core/interfaces.zig");
const websocket_adapter = @import("adapters/websocket/websocket_adapter.zig");
const websocket_text_source = @import("adapters/websocket/websocket_text_source.zig");
const websocket_state = @import("adapters/websocket/websocket_state.zig");
const http_publisher = @import("adapters/http/http_publisher.zig");

// Platform-conditional clipboard imports.
// Only the branch matching the current OS is compiled and type-checked.
const clipboard_impl = switch (builtin.os.tag) {
    .windows => struct {
        const paste = @import("adapters/windows/paste_windows.zig");
        const reader = @import("adapters/windows/clipboard_read_windows.zig");
    },
    .macos => struct {
        const mac = @import("adapters/macos/clipboard_mac.zig");
    },
    else => @compileError("Unsupported platform: only Windows and macOS are supported"),
};

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    // ── Shared adapters (cross-platform) ──────────────────────────────────────
    var ws_state = websocket_state.WebSocketState.init(allocator);
    defer ws_state.deinit();

    var ws_adapter = websocket_adapter.WebSocketAdapter.init(allocator, &ws_state, .{});
    var text_source = websocket_text_source.WebSocketTextSource.init(&ws_state);
    var publisher = http_publisher.HttpPublisher.init(allocator, .{});

    // ── Platform-specific clipboard adapters ──────────────────────────────────
    const adapters = switch (builtin.os.tag) {
        .windows => blk: {
            var paste = clipboard_impl.paste.WindowsPasteAdapter.init(allocator);
            var clip_reader = clipboard_impl.reader.WindowsClipboardReader.init(allocator);
            break :blk interfaces.AppAdapters{
                .tick = ws_adapter.asAdapter(),
                .text_source = text_source.asAdapter(),
                .paste = paste.asAdapter(),
                .clipboard_read = clip_reader.asAdapter(),
                .publish = publisher.asAdapter(),
            };
        },
        .macos => blk: {
            var mac_clip = clipboard_impl.mac.MacClipboardAdapter.init(allocator);
            break :blk interfaces.AppAdapters{
                .tick = ws_adapter.asAdapter(),
                .text_source = text_source.asAdapter(),
                .paste = mac_clip.asPasteAdapter(),
                .clipboard_read = mac_clip.asClipboardReadAdapter(),
                .publish = publisher.asAdapter(),
            };
        },
        else => @compileError("Unsupported platform"),
    };

    std.debug.print("Starting clipboard sync (bidirectional)...\n", .{});
    try app.runApp(allocator, adapters);
}
