const std = @import("std");

const TextMessage = struct {
    text: []const u8,
};

pub const ParseError = error{
    InvalidJson,
    MissingTextField,
    OutOfMemory,
};

pub fn parseTextMessage(allocator: std.mem.Allocator, json: []const u8) ParseError![]u8 {
    const parsed = std.json.parseFromSlice(TextMessage, allocator, json, .{}) catch {
        return ParseError.InvalidJson;
    };
    defer parsed.deinit();

    // Allocate and copy the text
    const text = allocator.alloc(u8, parsed.value.text.len) catch {
        return ParseError.OutOfMemory;
    };
    @memcpy(text, parsed.value.text);

    return text;
}

test "parseTextMessage valid json" {
    const allocator = std.testing.allocator;
    const json = "{\"text\": \"Hello World\"}";
    const result = try parseTextMessage(allocator, json);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World", result);
}

test "parseTextMessage unicode" {
    const allocator = std.testing.allocator;
    const json = "{\"text\": \"Olá Mundo 🌍\"}";
    const result = try parseTextMessage(allocator, json);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Olá Mundo 🌍", result);
}

test "parseTextMessage invalid json" {
    const allocator = std.testing.allocator;
    const json = "not json";
    const result = parseTextMessage(allocator, json);

    try std.testing.expectError(ParseError.InvalidJson, result);
}

test "parseTextMessage missing text field" {
    const allocator = std.testing.allocator;
    const json = "{\"other\": \"value\"}";
    const result = parseTextMessage(allocator, json);

    try std.testing.expectError(ParseError.InvalidJson, result);
}

test "parseTextMessage empty text" {
    const allocator = std.testing.allocator;
    const json = "{\"text\": \"\"}";
    const result = try parseTextMessage(allocator, json);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}
