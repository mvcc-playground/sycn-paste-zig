pub const TickCallback = *const fn (ctx: *anyopaque) anyerror!void;

pub const TickAdapter = struct {
    ctx: *anyopaque,
    run_loop_fn: *const fn (ctx: *anyopaque, on_tick: TickCallback, on_tick_ctx: *anyopaque) anyerror!void,
    deinit_fn: *const fn (ctx: *anyopaque) void,

    pub fn runLoop(self: TickAdapter, on_tick: TickCallback, on_tick_ctx: *anyopaque) !void {
        return self.run_loop_fn(self.ctx, on_tick, on_tick_ctx);
    }

    pub fn deinit(self: TickAdapter) void {
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
    tick: TickAdapter,
    text_source: TextSourceAdapter,
    paste: PasteAdapter,
};
