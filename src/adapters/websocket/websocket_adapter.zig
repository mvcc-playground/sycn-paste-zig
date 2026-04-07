const std = @import("std");
const interfaces = @import("../../core/interfaces.zig");
const WebSocketState = @import("websocket_state.zig").WebSocketState;
const json_parser = @import("json_parser.zig");
const win32 = @import("../windows/win32.zig");

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
    wsa_initialized: bool = false,

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

        // Initialize WinSock
        var wsa_data: win32.WSADATA = undefined;
        const wsa_result = win32.WSAStartup(0x0202, &wsa_data);
        if (wsa_result != 0) {
            std.debug.print("WSAStartup failed: {d}\n", .{wsa_result});
            return error.WSAStartupFailed;
        }
        self.wsa_initialized = true;
        defer {
            _ = win32.WSACleanup();
            self.wsa_initialized = false;
        }

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

            win32.Sleep(self.config.poll_interval_ms);
        }
    }

    fn pollOnce(self: *WebSocketAdapter, on_tick: interfaces.TickCallback, on_tick_ctx: *anyopaque) !void {
        var response_buf: [8192]u8 = undefined;

        const body = try httpGet(
            self.config.host,
            self.config.port,
            self.config.poll_endpoint,
            &response_buf,
        );

        if (body.len == 0) return;

        // Parse JSON response
        const text = json_parser.parseTextMessage(self.allocator, body) catch |err| {
            std.debug.print("Parse error: {any}\n", .{err});
            return;
        };
        defer self.allocator.free(text);

        // Skip empty text
        if (text.len == 0) return;

        // Only update if text changed
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

fn httpGet(host: []const u8, port: u16, path: []const u8, response_buf: []u8) ![]const u8 {
    // Create socket
    const sock = win32.socket(win32.AF_INET, win32.SOCK_STREAM, win32.IPPROTO_TCP);
    if (sock == win32.INVALID_SOCKET) {
        std.debug.print("Socket creation failed: {d}\n", .{win32.WSAGetLastError()});
        return error.SocketCreateFailed;
    }
    defer _ = win32.closesocket(sock);

    // Parse IP address (assumes dotted decimal format like "127.0.0.1")
    var ip_parts: [4]u8 = undefined;
    var part_idx: usize = 0;
    var current_num: u32 = 0;

    for (host) |c| {
        if (c == '.') {
            if (part_idx >= 4) return error.InvalidHost;
            ip_parts[part_idx] = @intCast(current_num);
            part_idx += 1;
            current_num = 0;
        } else if (c >= '0' and c <= '9') {
            current_num = current_num * 10 + (c - '0');
        } else {
            return error.InvalidHost;
        }
    }
    if (part_idx == 3) {
        ip_parts[3] = @intCast(current_num);
    } else {
        return error.InvalidHost;
    }

    // Connect
    var addr = win32.sockaddr_in{
        .sin_family = @intCast(win32.AF_INET),
        .sin_port = win32.htons(port),
        .sin_addr = @bitCast(ip_parts),
        .sin_zero = [_]u8{0} ** 8,
    };

    if (win32.connect(sock, &addr, @sizeOf(win32.sockaddr_in)) == win32.SOCKET_ERROR) {
        return error.ConnectFailed;
    }

    // Build and send HTTP request
    var request_buf: [512]u8 = undefined;
    const request = std.fmt.bufPrint(&request_buf, "GET {s} HTTP/1.1\r\nHost: {s}:{d}\r\nConnection: close\r\n\r\n", .{ path, host, port }) catch return error.RequestTooLarge;

    const sent = win32.send(sock, request.ptr, @intCast(request.len), 0);
    if (sent == win32.SOCKET_ERROR) {
        return error.SendFailed;
    }

    // Read response
    var total: usize = 0;
    while (total < response_buf.len) {
        const n = win32.recv(sock, response_buf[total..].ptr, @intCast(response_buf.len - total), 0);
        if (n == win32.SOCKET_ERROR) {
            return error.RecvFailed;
        }
        if (n == 0) break;
        total += @intCast(n);
    }

    if (total == 0) return "";

    // Find body (after \r\n\r\n)
    const response = response_buf[0..total];
    const header_end = std.mem.indexOf(u8, response, "\r\n\r\n") orelse return "";

    return response[header_end + 4 ..];
}
