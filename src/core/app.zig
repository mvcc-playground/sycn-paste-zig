const std = @import("std");
const interfaces = @import("interfaces.zig");

const HotkeyState = struct {
    text_source: interfaces.TextSourceAdapter,
    paste: interfaces.PasteAdapter,
};

fn onHotkey(ctx: *anyopaque) !void {
    const state: *HotkeyState = @ptrCast(@alignCast(ctx));
    const text = try state.text_source.getText();
    try state.paste.paste(text);
}

pub fn runApp(adapters: interfaces.AppAdapters) !void {
    var hotkey_state = HotkeyState{
        .text_source = adapters.text_source,
        .paste = adapters.paste,
    };
    defer adapters.hotkey.deinit();

    try adapters.hotkey.runLoop(onHotkey, &hotkey_state);
}

test "runApp triggers paste on hotkey callback" {
    var context = RunAppTestContext{ .text = "Hello world from zig" };
    const adapters = interfaces.AppAdapters{
        .hotkey = .{
            .ctx = &context,
            .run_loop_fn = runLoopFnForTest,
            .deinit_fn = deinitFnForTest,
        },
        .text_source = .{
            .ctx = &context,
            .get_text_fn = getTextFnForTest,
        },
        .paste = .{
            .ctx = &context,
            .paste_fn = pasteFnForTest,
        },
    };

    try runApp(adapters);
    try std.testing.expect(context.pasted);
}

const RunAppTestContext = struct {
    text: []const u8 = "",
    pasted: bool = false,
    hotkey_callback: ?interfaces.HotkeyCallback = null,
    hotkey_callback_ctx: ?*anyopaque = null,
};

fn runLoopFnForTest(ctx: *anyopaque, callback: interfaces.HotkeyCallback, callback_ctx: *anyopaque) !void {
    const test_ctx: *RunAppTestContext = @ptrCast(@alignCast(ctx));
    test_ctx.hotkey_callback = callback;
    test_ctx.hotkey_callback_ctx = callback_ctx;
    try callback(callback_ctx);
}

fn deinitFnForTest(_: *anyopaque) void {}

fn getTextFnForTest(ctx: *anyopaque) ![]const u8 {
    const test_ctx: *RunAppTestContext = @ptrCast(@alignCast(ctx));
    return test_ctx.text;
}

fn pasteFnForTest(ctx: *anyopaque, text: []const u8) !void {
    const test_ctx: *RunAppTestContext = @ptrCast(@alignCast(ctx));
    try std.testing.expectEqualStrings("Hello world from zig", text);
    test_ctx.pasted = true;
}
