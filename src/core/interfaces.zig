pub const HotkeyCallback = *const fn (ctx: *anyopaque) anyerror!void;

pub const HotkeyAdapter = struct {
    ctx: *anyopaque,
    run_loop_fn: *const fn (ctx: *anyopaque, on_hotkey: HotkeyCallback, on_hotkey_ctx: *anyopaque) anyerror!void,
    deinit_fn: *const fn (ctx: *anyopaque) void,

    pub fn runLoop(self: HotkeyAdapter, on_hotkey: HotkeyCallback, on_hotkey_ctx: *anyopaque) !void {
        return self.run_loop_fn(self.ctx, on_hotkey, on_hotkey_ctx);
    }

    pub fn deinit(self: HotkeyAdapter) void {
        self.deinit_fn(self.ctx);
    }
};

pub const TextSourceAdapter = struct {
    ctx: *anyopaque,
    get_text_fn: *const fn (ctx: *anyopaque) anyerror![]const u8,

    pub fn getText(self: TextSourceAdapter) ![]const u8 {
        return self.get_text_fn(self.ctx);
    }
};

pub const PasteAdapter = struct {
    ctx: *anyopaque,
    paste_fn: *const fn (ctx: *anyopaque, text: []const u8) anyerror!void,

    pub fn paste(self: PasteAdapter, text: []const u8) !void {
        return self.paste_fn(self.ctx, text);
    }
};

pub const AppAdapters = struct {
    hotkey: HotkeyAdapter,
    text_source: TextSourceAdapter,
    paste: PasteAdapter,
};
