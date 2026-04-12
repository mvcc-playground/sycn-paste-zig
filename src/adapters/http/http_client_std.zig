/// Cross-platform HTTP client using std.net (works on Windows and macOS).
/// Replaces the WinSock2-based httpGet in websocket_adapter.zig.
const std = @import("std");

/// Performs an HTTP GET request and returns the response body as a slice
/// into response_buf. The returned slice is valid as long as response_buf is.
pub fn httpGet(
    host: []const u8,
    port: u16,
    path: []const u8,
    response_buf: []u8,
) ![]const u8 {
    const addr = try std.net.Address.parseIp4(host, port);
    const stream = try std.net.tcpConnectToAddress(addr);
    defer stream.close();

    var request_buf: [512]u8 = undefined;
    const request = std.fmt.bufPrint(
        &request_buf,
        "GET {s} HTTP/1.1\r\nHost: {s}:{d}\r\nConnection: close\r\n\r\n",
        .{ path, host, port },
    ) catch return error.RequestTooLarge;

    try stream.writeAll(request);

    var total: usize = 0;
    while (total < response_buf.len) {
        const n = try stream.read(response_buf[total..]);
        if (n == 0) break;
        total += n;
    }
    if (total == 0) return "";

    const response = response_buf[0..total];
    const header_end = std.mem.indexOf(u8, response, "\r\n\r\n") orelse return "";
    return response[header_end + 4 ..];
}

/// Performs an HTTP POST request with a JSON body.
/// response_buf receives the response; the body slice is returned.
pub fn httpPost(
    host: []const u8,
    port: u16,
    path: []const u8,
    json_body: []const u8,
    response_buf: []u8,
) ![]const u8 {
    const addr = try std.net.Address.parseIp4(host, port);
    const stream = try std.net.tcpConnectToAddress(addr);
    defer stream.close();

    var header_buf: [1024]u8 = undefined;
    const header = std.fmt.bufPrint(
        &header_buf,
        "POST {s} HTTP/1.1\r\nHost: {s}:{d}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ path, host, port, json_body.len },
    ) catch return error.RequestTooLarge;

    try stream.writeAll(header);
    try stream.writeAll(json_body);

    var total: usize = 0;
    while (total < response_buf.len) {
        const n = try stream.read(response_buf[total..]);
        if (n == 0) break;
        total += n;
    }
    if (total == 0) return "";

    const response = response_buf[0..total];
    const header_end = std.mem.indexOf(u8, response, "\r\n\r\n") orelse return "";
    return response[header_end + 4 ..];
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "httpGet body extraction from raw HTTP response" {
    // Test the header-stripping logic in isolation
    const raw = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"text\":\"hello\"}";
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..raw.len], raw);
    const response = buf[0..raw.len];
    const header_end = std.mem.indexOf(u8, response, "\r\n\r\n") orelse return error.TestUnexpectedResult;
    const body = response[header_end + 4 ..];
    try std.testing.expectEqualStrings("{\"text\":\"hello\"}", body);
}

test "httpPost header construction fits in buffer" {
    // Verify the header format doesn't overflow for typical inputs
    var header_buf: [1024]u8 = undefined;
    const json_body = "{\"text\":\"hello world\"}";
    const header = try std.fmt.bufPrint(
        &header_buf,
        "POST {s} HTTP/1.1\r\nHost: {s}:{d}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ "/messages", "127.0.0.1", 8000, json_body.len },
    );
    try std.testing.expect(header.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, header, "POST /messages"));
}
