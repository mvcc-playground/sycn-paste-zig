const interfaces = @import("../../core/interfaces.zig");
const win32 = @import("win32.zig");

pub const WindowsHotkeyAdapter = struct {
    id: i32,

    pub fn init() !WindowsHotkeyAdapter {
        const id: i32 = 1;
        if (win32.RegisterHotKey(null, id, win32.MOD_CONTROL, win32.VK_B) == 0) {
            return error.RegisterHotKeyFailed;
        }
        return .{ .id = id };
    }

    pub fn asAdapter(self: *WindowsHotkeyAdapter) interfaces.HotkeyAdapter {
        return .{
            .ctx = self,
            .run_loop_fn = runLoop,
            .deinit_fn = deinit,
        };
    }

    fn runLoop(ctx: *anyopaque, on_hotkey: interfaces.HotkeyCallback, on_hotkey_ctx: *anyopaque) !void {
        const self: *WindowsHotkeyAdapter = @ptrCast(@alignCast(ctx));
        var msg: win32.MSG = undefined;

        while (true) {
            const status = win32.GetMessageW(&msg, null, 0, 0);
            if (status == -1) return error.GetMessageFailed;
            if (status == 0) return;

            if (msg.message == win32.WM_HOTKEY and msg.wParam == @as(usize, @intCast(self.id))) {
                try on_hotkey(on_hotkey_ctx);
            }
        }
    }

    fn deinit(ctx: *anyopaque) void {
        const self: *WindowsHotkeyAdapter = @ptrCast(@alignCast(ctx));
        _ = win32.UnregisterHotKey(null, self.id);
    }
};
