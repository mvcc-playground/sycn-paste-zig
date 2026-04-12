/// PublishAdapter implementation: sends clipboard text to the sync server via HTTP POST.
const std = @import("std");
const interfaces = @import("../../core/interfaces.zig");
const http_client = @import("http_client_std.zig");

pub const Config = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8000,
    publish_endpoint: []const u8 = "/messages",
};

pub const HttpPublisher = struct {
    allocator: std.mem.Allocator,
    config: Config,

    pub fn init(allocator: std.mem.Allocator, config: Config) HttpPublisher {
        return .{ .allocator = allocator, .config = config };
    }

    pub fn asAdapter(self: *HttpPublisher) interfaces.PublishAdapter {
        return .{
            .ctx = @ptrCast(self),
            .publish_fn = publish,
        };
    }

    fn publish(ctx: *anyopaque, text: []const u8) anyerror!void {
        const self: *HttpPublisher = @ptrCast(@alignCast(ctx));

        // Use std.json for correct escaping of special characters in text
        const Payload = struct { text: []const u8 };
        const json_body = try std.json.stringifyAlloc(
            self.allocator,
            Payload{ .text = text },
            .{},
        );
        defer self.allocator.free(json_body);

        var response_buf: [2048]u8 = undefined;
        _ = try http_client.httpPost(
            self.config.host,
            self.config.port,
            self.config.publish_endpoint,
            json_body,
            &response_buf,
        );

        std.debug.print("Published: {s}\n", .{text});
    }
};

// ─── Tests ───────────────────────────────────────────────────────────────────

test "HttpPublisher JSON serialization escapes special chars" {
    const allocator = std.testing.allocator;
    const Payload = struct { text: []const u8 };

    // Text with quotes and backslashes must be properly escaped
    const json = try std.json.stringifyAlloc(
        allocator,
        Payload{ .text = "hello \"world\" \\ test" },
        .{},
    );
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"text\":\"hello \\\"world\\\" \\\\ test\"}",
        json,
    );
}

test "HttpPublisher JSON serialization with unicode" {
    const allocator = std.testing.allocator;
    const Payload = struct { text: []const u8 };

    const json = try std.json.stringifyAlloc(
        allocator,
        Payload{ .text = "Olá Mundo" },
        .{},
    );
    defer allocator.free(json);

    try std.testing.expect(json.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, json, "{\"text\":"));
}
