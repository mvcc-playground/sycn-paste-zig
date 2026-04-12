/// Windows clipboard reader adapter using GetClipboardData (CF_UNICODETEXT).
/// Implements ClipboardReadAdapter: reads the current clipboard as UTF-8.
const std = @import("std");
const interfaces = @import("../../core/interfaces.zig");
const win32 = @import("win32.zig");

pub const WindowsClipboardReader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WindowsClipboardReader {
        return .{ .allocator = allocator };
    }

    pub fn asAdapter(self: *WindowsClipboardReader) interfaces.ClipboardReadAdapter {
        return .{
            .ctx = @ptrCast(self),
            .read_fn = read,
        };
    }

    /// Reads the current clipboard text (CF_UNICODETEXT) and returns it as
    /// a UTF-8 owned slice. The caller must free it.
    fn read(ctx: *anyopaque, allocator: std.mem.Allocator) anyerror![]u8 {
        _ = ctx; // no instance state needed

        if (win32.OpenClipboard(null) == 0) {
            return allocator.dupe(u8, "");
        }
        defer _ = win32.CloseClipboard();

        const handle = win32.GetClipboardData(win32.CF_UNICODETEXT);
        if (handle == null) {
            return allocator.dupe(u8, "");
        }

        const ptr = win32.GlobalLock(handle);
        if (ptr == null) {
            return allocator.dupe(u8, "");
        }
        defer _ = win32.GlobalUnlock(handle);

        // The clipboard data is a null-terminated UTF-16LE string
        const utf16_ptr: [*:0]const u16 = @ptrCast(@alignCast(ptr));
        const utf16_len = std.mem.len(utf16_ptr);
        if (utf16_len == 0) {
            return allocator.dupe(u8, "");
        }

        const utf16_slice = utf16_ptr[0..utf16_len];
        const utf8 = try std.unicode.utf16LeToUtf8Alloc(allocator, utf16_slice);
        return utf8;
    }
};

// ─── Tests ───────────────────────────────────────────────────────────────────

test "WindowsClipboardReader initializes and exposes adapter" {
    var reader = WindowsClipboardReader.init(std.testing.allocator);
    const adapter = reader.asAdapter();
    try std.testing.expectEqual(@as(*anyopaque, @ptrCast(&reader)), adapter.ctx);
}
