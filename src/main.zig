const std = @import("std");
const app = @import("core/app.zig");
const incrementing_text = @import("adapters/text/incrementing_text.zig");
const tick_windows = @import("adapters/windows/tick_windows.zig");
const paste_windows = @import("adapters/windows/paste_windows.zig");
const interfaces = @import("core/interfaces.zig");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var tick = tick_windows.WindowsTickAdapter.init(10_000);
    var text_source = incrementing_text.IncrementingTextSource.init();
    var paste = paste_windows.WindowsPasteAdapter.init(allocator);

    const adapters = interfaces.AppAdapters{
        .tick = tick.asAdapter(),
        .text_source = text_source.asAdapter(),
        .paste = paste.asAdapter(),
    };

    std.debug.print("Running in background. Updating clipboard on each new message tick (10s).\n", .{});
    try app.runApp(adapters);
}
