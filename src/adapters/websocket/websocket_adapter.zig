const std = @import("std");
const interfaces = @import("../../core/interfaces.zig");
const WebSocketState = @import("websocket_state.zig").WebSocketState;
const json_parser = @import("json_parser.zig");
const http_client = @import("../http/http_client_std.zig");

pub const Config = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8000,
    poll_endpoint: []const u8 = "/poll",
    poll_interval_ms: u32 = 500,
};

pub const WebSocketAdapter = struct {
    state: *WebSocketState,
    allocator: std.mem.Allocator,
    config: Config,

    pub fn init(allocator: std.mem.Allocator, state: *WebSocketState, config: Config) WebSocketAdapter {
        return .{
            .allocator = allocator,
            .state = state,
            .config = config,
        };
    }

    pub fn asAdapter(self: *WebSocketAdapter) interfaces.TickAdapter {
        return .{
            .ctx = @ptrCast(self),
            .run_loop_fn = runLoop,
            .deinit_fn = deinitFn,
        };
    }

    fn runLoop(ctx: *anyopaque, on_tick: interfaces.TickCallback, on_tick_ctx: *anyopaque) anyerror!void {
        const self: *WebSocketAdapter = @ptrCast(@alignCast(ctx));

        std.debug.print("Polling http://{s}:{d}{s} every {d}ms...\n", .{
            self.config.host,
            self.config.port,
            self.config.poll_endpoint,
            self.config.poll_interval_ms,
        });

        while (self.state.isRunning()) {
            self.pollOnce(on_tick, on_tick_ctx) catch |err| {
                std.debug.print("Poll error: {any}. Retrying...\n", .{err});
            };

            std.time.sleep(@as(u64, self.config.poll_interval_ms) * std.time.ns_per_ms);
        }
    }

    fn pollOnce(self: *WebSocketAdapter, on_tick: interfaces.TickCallback, on_tick_ctx: *anyopaque) !void {
        var response_buf: [8192]u8 = undefined;

        const body = try http_client.httpGet(
            self.config.host,
            self.config.port,
            self.config.poll_endpoint,
            &response_buf,
        );

        if (body.len == 0) return;

        const text = json_parser.parseTextMessage(self.allocator, body) catch |err| {
            std.debug.print("Parse error: {any}\n", .{err});
            return;
        };
        defer self.allocator.free(text);

        if (text.len == 0) return;

        // Only update state and trigger tick if text changed
        const current = self.state.getText();
        if (current == null or !std.mem.eql(u8, current.?, text)) {
            try self.state.setText(text);
            std.debug.print("New message: {s}\n", .{text});
            try on_tick(on_tick_ctx);
        }
    }

    fn deinitFn(ctx: *anyopaque) void {
        const self: *WebSocketAdapter = @ptrCast(@alignCast(ctx));
        self.state.stop();
    }
};
