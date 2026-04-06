const std = @import("std");
const interfaces = @import("../../core/interfaces.zig");
const win32 = @import("win32.zig");

pub const WindowsPasteAdapter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WindowsPasteAdapter {
        return .{ .allocator = allocator };
    }

    pub fn asAdapter(self: *WindowsPasteAdapter) interfaces.PasteAdapter {
        return .{
            .ctx = self,
            .paste_fn = paste,
        };
    }

    fn paste(ctx: *anyopaque, text: []const u8) !void {
        const self: *WindowsPasteAdapter = @ptrCast(@alignCast(ctx));
        try self.setClipboardUnicodeText(text);
    }

    fn setClipboardUnicodeText(self: *WindowsPasteAdapter, text: []const u8) !void {
        const utf16 = try std.unicode.utf8ToUtf16LeAlloc(self.allocator, text);
        defer self.allocator.free(utf16);

        const bytes_len = (utf16.len + 1) * @sizeOf(u16);
        const hmem = win32.GlobalAlloc(win32.GMEM_MOVEABLE, bytes_len) orelse return error.GlobalAllocFailed;
        errdefer _ = win32.GlobalFree(hmem);

        const raw_ptr = win32.GlobalLock(hmem) orelse return error.GlobalLockFailed;
        const buffer_ptr: [*]u16 = @ptrCast(@alignCast(raw_ptr));

        std.mem.copyForwards(u16, buffer_ptr[0..utf16.len], utf16);
        buffer_ptr[utf16.len] = 0;

        _ = win32.GlobalUnlock(hmem);

        if (win32.OpenClipboard(null) == 0) return error.OpenClipboardFailed;
        defer _ = win32.CloseClipboard();

        if (win32.EmptyClipboard() == 0) return error.EmptyClipboardFailed;
        if (win32.SetClipboardData(win32.CF_UNICODETEXT, hmem) == null) return error.SetClipboardDataFailed;
    }

};
