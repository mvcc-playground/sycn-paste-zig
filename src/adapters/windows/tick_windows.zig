const interfaces = @import("../../core/interfaces.zig");
const win32 = @import("win32.zig");

pub const WindowsTickAdapter = struct {
    interval_ms: u32,
    running: bool,

    pub fn init(interval_ms: u32) WindowsTickAdapter {
        return .{
            .interval_ms = interval_ms,
            .running = true,
        };
    }

    pub fn asAdapter(self: *WindowsTickAdapter) interfaces.TickAdapter {
        return .{
            .ctx = self,
            .run_loop_fn = runLoop,
            .deinit_fn = deinit,
        };
    }

    fn runLoop(ctx: *anyopaque, on_tick: interfaces.TickCallback, on_tick_ctx: *anyopaque) !void {
        const self: *WindowsTickAdapter = @ptrCast(@alignCast(ctx));
        while (self.running) {
            win32.Sleep(self.interval_ms);
            if (!self.running) return;
            try on_tick(on_tick_ctx);
        }
    }

    fn deinit(ctx: *anyopaque) void {
        const self: *WindowsTickAdapter = @ptrCast(@alignCast(ctx));
        self.running = false;
    }
};
