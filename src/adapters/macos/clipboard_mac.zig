/// macOS clipboard adapter using NSPasteboard via Objective-C runtime.
/// Implements both PasteAdapter (write) and ClipboardReadAdapter (read).
///
/// Linking requirement: add `exe.root_module.addFramework("AppKit")` in build.zig.
const std = @import("std");
const interfaces = @import("../../core/interfaces.zig");

// Objective-C runtime types
const id = ?*anyopaque;
const SEL = ?*anyopaque;
const Class = ?*anyopaque;

// Objective-C runtime functions
extern fn objc_getClass(name: [*:0]const u8) Class;
extern fn sel_registerName(name: [*:0]const u8) SEL;
extern fn objc_msgSend() void;

// We call objc_msgSend with the correct signature by casting it.
// Signatures used:
//   id  msgSend_id(id, SEL) — zero-arg method returning id
//   id  msgSend_id_id(id, SEL, id) — one-arg method returning id
//   void msgSend_void_id(id, SEL, id) — one-arg method returning void
//   i64 msgSend_i64(id, SEL) — zero-arg method returning NSInteger (i64 on 64-bit)
//   u8  msgSend_bool(id, SEL) — zero-arg method returning BOOL
const MsgSendId = *const fn (id, SEL) callconv(.C) id;
const MsgSendIdId = *const fn (id, SEL, id) callconv(.C) id;
const MsgSendVoidId = *const fn (id, SEL, id) callconv(.C) void;
const MsgSendVoidIdId = *const fn (id, SEL, id, id) callconv(.C) void;
const MsgSendI64 = *const fn (id, SEL) callconv(.C) i64;
const MsgSendBool = *const fn (id, SEL, id, id) callconv(.C) bool;

fn msgSendId(receiver: id, sel: SEL) id {
    return @as(MsgSendId, @ptrCast(&objc_msgSend))(receiver, sel);
}

fn msgSendIdId(receiver: id, sel: SEL, arg: id) id {
    return @as(MsgSendIdId, @ptrCast(&objc_msgSend))(receiver, sel, arg);
}

fn msgSendVoidId(receiver: id, sel: SEL, arg: id) void {
    @as(MsgSendVoidId, @ptrCast(&objc_msgSend))(receiver, sel, arg);
}

fn msgSendI64(receiver: id, sel: SEL) i64 {
    return @as(MsgSendI64, @ptrCast(&objc_msgSend))(receiver, sel);
}

fn msgSendBool(receiver: id, sel: SEL, arg0: id, arg1: id) bool {
    return @as(MsgSendBool, @ptrCast(&objc_msgSend))(receiver, sel, arg0, arg1);
}

/// Cached selectors and classes (initialized once).
const ObjcHandles = struct {
    NSPasteboard: Class,
    NSString: Class,
    NSArray: Class,
    sel_generalPasteboard: SEL,
    sel_changeCount: SEL,
    sel_stringForType: SEL,
    sel_stringWithUTF8String: SEL,
    sel_UTF8String: SEL,
    sel_clearContents: SEL,
    sel_setString_forType: SEL,
    sel_arrayWithObject: SEL,
    // NSPasteboardTypeString is a global NSString constant; we load it via the class method
    NSPasteboardTypeString: id,

    fn init() ObjcHandles {
        const NSString_class = objc_getClass("NSString");
        const NSArray_class = objc_getClass("NSArray");
        const NSPasteboard_class = objc_getClass("NSPasteboard");

        // Build the NSPasteboardTypeString constant value by creating an NSString
        // with the known value "public.utf8-plain-text"
        const sel_strWithUTF8 = sel_registerName("stringWithUTF8String:");
        const pb_type_str: id = @as(MsgSendIdId, @ptrCast(&objc_msgSend))(
            NSString_class,
            sel_strWithUTF8,
            @ptrCast(@constCast("public.utf8-plain-text")),
        );

        return .{
            .NSPasteboard = NSPasteboard_class,
            .NSString = NSString_class,
            .NSArray = NSArray_class,
            .sel_generalPasteboard = sel_registerName("generalPasteboard"),
            .sel_changeCount = sel_registerName("changeCount"),
            .sel_stringForType = sel_registerName("stringForType:"),
            .sel_stringWithUTF8String = sel_strWithUTF8,
            .sel_UTF8String = sel_registerName("UTF8String"),
            .sel_clearContents = sel_registerName("clearContents"),
            .sel_setString_forType = sel_registerName("setString:forType:"),
            .sel_arrayWithObject = sel_registerName("arrayWithObject:"),
            .NSPasteboardTypeString = pb_type_str,
        };
    }
};

// Module-level lazy initialization of Obj-C handles
var objc_handles: ?ObjcHandles = null;

fn getHandles() *ObjcHandles {
    if (objc_handles == null) {
        objc_handles = ObjcHandles.init();
    }
    return &objc_handles.?;
}

pub const MacClipboardAdapter = struct {
    allocator: std.mem.Allocator,
    /// Tracks NSPasteboard.changeCount to detect clipboard changes efficiently.
    /// -1 means "not yet read". If changeCount matches, we skip reading content.
    last_change_count: i64 = -1,

    pub fn init(allocator: std.mem.Allocator) MacClipboardAdapter {
        return .{ .allocator = allocator };
    }

    pub fn asPasteAdapter(self: *MacClipboardAdapter) interfaces.PasteAdapter {
        return .{
            .ctx = @ptrCast(self),
            .paste_fn = paste,
        };
    }

    pub fn asClipboardReadAdapter(self: *MacClipboardAdapter) interfaces.ClipboardReadAdapter {
        return .{
            .ctx = @ptrCast(self),
            .read_fn = read,
        };
    }

    /// Writes text to the macOS clipboard via NSPasteboard.
    fn paste(ctx: *anyopaque, text: []const u8) anyerror!void {
        const self: *MacClipboardAdapter = @ptrCast(@alignCast(ctx));
        const h = getHandles();

        const pb: id = msgSendId(h.NSPasteboard, h.sel_generalPasteboard);
        if (pb == null) return error.NoPasteboard;

        // [pb clearContents]
        _ = msgSendId(pb, h.sel_clearContents);

        // NSString* nsStr = [NSString stringWithUTF8String:text_cstr]
        // We need a null-terminated copy of text
        const cstr = try self.allocator.dupeZ(u8, text);
        defer self.allocator.free(cstr);

        const ns_str: id = @as(MsgSendIdId, @ptrCast(&objc_msgSend))(
            h.NSString,
            h.sel_stringWithUTF8String,
            @ptrCast(cstr.ptr),
        );
        if (ns_str == null) return error.NSStringCreationFailed;

        // [pb setString:nsStr forType:NSPasteboardTypeString]
        const MsgSendVoidIdIdLocal = *const fn (id, SEL, id, id) callconv(.C) void;
        @as(MsgSendVoidIdIdLocal, @ptrCast(&objc_msgSend))(
            pb,
            h.sel_setString_forType,
            ns_str,
            h.NSPasteboardTypeString,
        );

        // Update change count so our next read doesn't re-publish what we just wrote
        self.last_change_count = msgSendI64(pb, h.sel_changeCount);
    }

    /// Reads text from the macOS clipboard.
    /// Returns an owned slice (caller must free). Returns empty string if clipboard
    /// has no text or hasn't changed since last read.
    fn read(ctx: *anyopaque, allocator: std.mem.Allocator) anyerror![]u8 {
        const self: *MacClipboardAdapter = @ptrCast(@alignCast(ctx));
        const h = getHandles();

        const pb: id = msgSendId(h.NSPasteboard, h.sel_generalPasteboard);
        if (pb == null) return allocator.dupe(u8, "");

        // Check changeCount first — avoids reading content when nothing changed
        const current_change_count = msgSendI64(pb, h.sel_changeCount);
        if (current_change_count == self.last_change_count) {
            return allocator.dupe(u8, "");
        }
        self.last_change_count = current_change_count;

        // NSString* str = [pb stringForType:NSPasteboardTypeString]
        const ns_str: id = @as(MsgSendIdId, @ptrCast(&objc_msgSend))(
            pb,
            h.sel_stringForType,
            h.NSPasteboardTypeString,
        );
        if (ns_str == null) return allocator.dupe(u8, "");

        // const char* utf8 = [str UTF8String]
        const MsgSendCStr = *const fn (id, SEL) callconv(.C) [*:0]const u8;
        const utf8_ptr: ?[*:0]const u8 = @as(MsgSendCStr, @ptrCast(&objc_msgSend))(ns_str, h.sel_UTF8String);
        if (utf8_ptr == null) return allocator.dupe(u8, "");

        const utf8_slice = std.mem.span(utf8_ptr.?);
        return allocator.dupe(u8, utf8_slice);
    }
};

// ─── Tests ───────────────────────────────────────────────────────────────────

test "MacClipboardAdapter initializes without error" {
    const adapter = MacClipboardAdapter.init(std.testing.allocator);
    try std.testing.expectEqual(@as(i64, -1), adapter.last_change_count);
}

test "MacClipboardAdapter exposes correct vtable adapters" {
    var adapter = MacClipboardAdapter.init(std.testing.allocator);
    const paste_adapter = adapter.asPasteAdapter();
    const read_adapter = adapter.asClipboardReadAdapter();
    // Verify ctx pointers are the same adapter instance
    try std.testing.expectEqual(@as(*anyopaque, @ptrCast(&adapter)), paste_adapter.ctx);
    try std.testing.expectEqual(@as(*anyopaque, @ptrCast(&adapter)), read_adapter.ctx);
}
