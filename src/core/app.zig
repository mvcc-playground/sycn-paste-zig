const std = @import("std");
const interfaces = @import("interfaces.zig");

/// State shared across ticks. Owns last_received and last_published strings
/// to prevent echo loops in bidirectional sync.
const TickState = struct {
    allocator: std.mem.Allocator,
    text_source: interfaces.TextSourceAdapter,
    paste: interfaces.PasteAdapter,
    clipboard_read: ?interfaces.ClipboardReadAdapter,
    publish: ?interfaces.PublishAdapter,
    /// Last text written to local clipboard from the server.
    /// Used to avoid re-publishing text we just received.
    last_received: ?[]u8 = null,
    /// Last text we published to the server from local clipboard.
    /// Used to avoid publishing the same content twice.
    last_published: ?[]u8 = null,

    fn deinit(self: *TickState) void {
        if (self.last_received) |s| self.allocator.free(s);
        if (self.last_published) |s| self.allocator.free(s);
    }
};

fn differs(a: []const u8, b: ?[]u8) bool {
    const b_val = b orelse return true;
    return !std.mem.eql(u8, a, b_val);
}

fn onTick(ctx: *anyopaque) !void {
    const state: *TickState = @ptrCast(@alignCast(ctx));

    // === Direction 1: Server → Local Clipboard ===
    const server_text = try state.text_source.getText();

    if (server_text.len > 0 and differs(server_text, state.last_received)) {
        try state.paste.paste(server_text);

        if (state.last_received) |old| state.allocator.free(old);
        state.last_received = try state.allocator.dupe(u8, server_text);
    }

    // === Direction 2: Local Clipboard → Server ===
    // Only active when both clipboard_read and publish adapters are provided.
    if (state.clipboard_read) |cr| {
        if (state.publish) |pub_adapter| {
            const raw = try cr.read(state.allocator);
            defer state.allocator.free(raw);

            // Trim trailing newlines/spaces that some platforms append (e.g. pbpaste)
            const trimmed = std.mem.trimRight(u8, raw, "\n\r ");

            // Publish only when:
            //   (a) not empty
            //   (b) different from last thing we published (avoid duplicate sends)
            //   (c) different from last thing received from server (avoid echo loop)
            if (trimmed.len > 0 and
                differs(trimmed, state.last_published) and
                differs(trimmed, state.last_received))
            {
                try pub_adapter.publish(trimmed);

                if (state.last_published) |old| state.allocator.free(old);
                state.last_published = try state.allocator.dupe(u8, trimmed);
            }
        }
    }
}

pub fn runApp(allocator: std.mem.Allocator, adapters: interfaces.AppAdapters) !void {
    var tick_state = TickState{
        .allocator = allocator,
        .text_source = adapters.text_source,
        .paste = adapters.paste,
        .clipboard_read = adapters.clipboard_read,
        .publish = adapters.publish,
    };
    defer tick_state.deinit();
    defer adapters.tick.deinit();

    try adapters.tick.runLoop(onTick, &tick_state);
}

// ─── Tests ───────────────────────────────────────────────────────────────────

const TestCtx = struct {
    // server text to return
    server_text: []const u8 = "",
    // local clipboard text to return
    clipboard_text: []const u8 = "",
    // recorded paste output (points to server_text literal — static lifetime)
    pasted_text: []const u8 = "",
    // published text stored in a fixed buffer to avoid dangling refs
    // (publish receives a slice into a temp buffer freed after onTick returns)
    publish_buf: [1024]u8 = [_]u8{0} ** 1024,
    published_len: usize = 0,
    tick_callback: ?interfaces.TickCallback = null,
    tick_callback_ctx: ?*anyopaque = null,

    fn publishedText(self: *const TestCtx) []const u8 {
        return self.publish_buf[0..self.published_len];
    }
};

fn runLoopFnForTest(ctx: *anyopaque, callback: interfaces.TickCallback, callback_ctx: *anyopaque) !void {
    const c: *TestCtx = @ptrCast(@alignCast(ctx));
    c.tick_callback = callback;
    c.tick_callback_ctx = callback_ctx;
    try callback(callback_ctx);
}

fn deinitFnForTest(_: *anyopaque) void {}

fn getTextFnForTest(ctx: *anyopaque) ![]const u8 {
    const c: *TestCtx = @ptrCast(@alignCast(ctx));
    return c.server_text;
}

fn pasteFnForTest(ctx: *anyopaque, text: []const u8) !void {
    const c: *TestCtx = @ptrCast(@alignCast(ctx));
    c.pasted_text = text;
}

fn clipboardReadFnForTest(ctx: *anyopaque, _: std.mem.Allocator) ![]u8 {
    const c: *TestCtx = @ptrCast(@alignCast(ctx));
    // Return a copy so the caller can free it
    return std.testing.allocator.dupe(u8, c.clipboard_text);
}

fn publishFnForTest(ctx: *anyopaque, text: []const u8) !void {
    const c: *TestCtx = @ptrCast(@alignCast(ctx));
    // Copy into fixed buffer — text is a slice into a temp allocation freed after onTick
    @memcpy(c.publish_buf[0..text.len], text);
    c.published_len = text.len;
}

fn makeAdapters(ctx: *TestCtx, include_bidir: bool) interfaces.AppAdapters {
    return interfaces.AppAdapters{
        .tick = .{
            .ctx = @ptrCast(ctx),
            .run_loop_fn = runLoopFnForTest,
            .deinit_fn = deinitFnForTest,
        },
        .text_source = .{
            .ctx = @ptrCast(ctx),
            .get_text_fn = getTextFnForTest,
        },
        .paste = .{
            .ctx = @ptrCast(ctx),
            .paste_fn = pasteFnForTest,
        },
        .clipboard_read = if (include_bidir) interfaces.ClipboardReadAdapter{
            .ctx = @ptrCast(ctx),
            .read_fn = clipboardReadFnForTest,
        } else null,
        .publish = if (include_bidir) interfaces.PublishAdapter{
            .ctx = @ptrCast(ctx),
            .publish_fn = publishFnForTest,
        } else null,
    };
}

test "runApp pastes server text to local clipboard" {
    var ctx = TestCtx{ .server_text = "Hello from server" };
    const adapters = makeAdapters(&ctx, false);
    try runApp(std.testing.allocator, adapters);
    try std.testing.expectEqualStrings("Hello from server", ctx.pasted_text);
}

test "runApp bidirectional: server text is pasted and last_received updated" {
    var ctx = TestCtx{ .server_text = "sync text", .clipboard_text = "" };
    const adapters = makeAdapters(&ctx, true);
    try runApp(std.testing.allocator, adapters);
    try std.testing.expectEqualStrings("sync text", ctx.pasted_text);
    // clipboard_text is empty so nothing should be published
    try std.testing.expectEqualStrings("", ctx.publishedText());
}

test "runApp bidirectional: local clipboard change is published to server" {
    var ctx = TestCtx{ .server_text = "", .clipboard_text = "user copied this" };
    const adapters = makeAdapters(&ctx, true);
    try runApp(std.testing.allocator, adapters);
    try std.testing.expectEqualStrings("user copied this", ctx.publishedText());
}

test "runApp bidirectional: anti-loop prevents re-publishing received text" {
    // Server sends text, client writes to clipboard; on next read the same
    // text appears in clipboard but must NOT be published back.
    var ctx = TestCtx{ .server_text = "from server", .clipboard_text = "from server" };
    const adapters = makeAdapters(&ctx, true);
    try runApp(std.testing.allocator, adapters);
    // pasted because server sent it
    try std.testing.expectEqualStrings("from server", ctx.pasted_text);
    // NOT published because it matches last_received
    try std.testing.expectEqualStrings("", ctx.publishedText());
}

test "runApp bidirectional: empty clipboard text is not published" {
    var ctx = TestCtx{ .server_text = "", .clipboard_text = "" };
    const adapters = makeAdapters(&ctx, true);
    try runApp(std.testing.allocator, adapters);
    try std.testing.expectEqualStrings("", ctx.publishedText());
}

test "runApp bidirectional: whitespace-only clipboard is not published" {
    var ctx = TestCtx{ .server_text = "", .clipboard_text = "\n\r " };
    const adapters = makeAdapters(&ctx, true);
    try runApp(std.testing.allocator, adapters);
    try std.testing.expectEqualStrings("", ctx.publishedText());
}
