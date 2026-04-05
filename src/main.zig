const std = @import("std");
const app = @import("core/app.zig");
const fixed_text = @import("adapters/text/fixed_text.zig");
const hotkey_windows = @import("adapters/windows/hotkey_windows.zig");
const paste_windows = @import("adapters/windows/paste_windows.zig");
const interfaces = @import("core/interfaces.zig");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var hotkey = try hotkey_windows.WindowsHotkeyAdapter.init();
    var text_source = fixed_text.FixedTextSource.init("Hello world from zig");
    var paste = paste_windows.WindowsPasteAdapter.init(allocator);

    const adapters = interfaces.AppAdapters{
        .hotkey = hotkey.asAdapter(),
        .text_source = text_source.asAdapter(),
        .paste = paste.asAdapter(),
    };

    std.debug.print("Running in background. Press Ctrl+B to paste text.\n", .{});
    try app.runApp(adapters);
}
