const std = @import("std");

pub const WebSocketState = struct {
    allocator: std.mem.Allocator,
    current_text: ?[]u8 = null,
    mutex: std.Thread.Mutex = .{},
    running: bool = true,

    pub fn init(allocator: std.mem.Allocator) WebSocketState {
        return .{
            .allocator = allocator,
        };
    }

    pub fn setText(self: *WebSocketState, text: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Free old text if exists
        if (self.current_text) |old| {
            self.allocator.free(old);
        }

        // Allocate and copy new text
        const new_text = try self.allocator.alloc(u8, text.len);
        @memcpy(new_text, text);
        self.current_text = new_text;
    }

    pub fn getText(self: *WebSocketState) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.current_text;
    }

    pub fn stop(self: *WebSocketState) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.running = false;
    }

    pub fn isRunning(self: *WebSocketState) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.running;
    }

    pub fn deinit(self: *WebSocketState) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.current_text) |text| {
            self.allocator.free(text);
            self.current_text = null;
        }
    }
};

test "WebSocketState basic set and get" {
    const allocator = std.testing.allocator;
    var state = WebSocketState.init(allocator);
    defer state.deinit();

    try state.setText("hello");
    const text = state.getText();
    try std.testing.expectEqualStrings("hello", text.?);
}

test "WebSocketState overwrites previous text" {
    const allocator = std.testing.allocator;
    var state = WebSocketState.init(allocator);
    defer state.deinit();

    try state.setText("first");
    try state.setText("second");
    const text = state.getText();
    try std.testing.expectEqualStrings("second", text.?);
}

test "WebSocketState returns null when no text set" {
    const allocator = std.testing.allocator;
    var state = WebSocketState.init(allocator);
    defer state.deinit();

    try std.testing.expectEqual(null, state.getText());
}

test "WebSocketState stop and isRunning" {
    const allocator = std.testing.allocator;
    var state = WebSocketState.init(allocator);
    defer state.deinit();

    try std.testing.expect(state.isRunning());
    state.stop();
    try std.testing.expect(!state.isRunning());
}
