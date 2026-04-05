pub const BOOL = i32;
pub const WORD = u16;
pub const DWORD = u32;
pub const UINT = u32;
pub const ULONG_PTR = usize;
pub const LONG = i32;
pub const HANDLE = ?*anyopaque;
pub const HWND = ?*anyopaque;

pub const POINT = extern struct {
    x: LONG,
    y: LONG,
};

pub const MSG = extern struct {
    hwnd: HWND,
    message: UINT,
    wParam: usize,
    lParam: isize,
    time: DWORD,
    pt: POINT,
    lPrivate: DWORD,
};

pub const KEYBDINPUT = extern struct {
    wVk: WORD,
    wScan: WORD,
    dwFlags: DWORD,
    time: DWORD,
    dwExtraInfo: ULONG_PTR,
};

pub const MOUSEINPUT = extern struct {
    dx: LONG,
    dy: LONG,
    mouseData: DWORD,
    dwFlags: DWORD,
    time: DWORD,
    dwExtraInfo: ULONG_PTR,
};

pub const HARDWAREINPUT = extern struct {
    uMsg: DWORD,
    wParamL: WORD,
    wParamH: WORD,
};

pub const INPUT_UNION = extern union {
    mi: MOUSEINPUT,
    ki: KEYBDINPUT,
    hi: HARDWAREINPUT,
};

pub const INPUT = extern struct {
    type: DWORD,
    data: INPUT_UNION,
};

pub const MOD_CONTROL: UINT = 0x0002;
pub const WM_HOTKEY: UINT = 0x0312;
pub const VK_B: UINT = 0x42;
pub const VK_CONTROL: WORD = 0x11;
pub const VK_V: WORD = 0x56;
pub const KEYEVENTF_KEYUP: DWORD = 0x0002;
pub const INPUT_KEYBOARD: DWORD = 1;
pub const CF_UNICODETEXT: UINT = 13;
pub const GMEM_MOVEABLE: UINT = 0x0002;

pub extern "user32" fn RegisterHotKey(hWnd: HWND, id: i32, fsModifiers: UINT, vk: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn UnregisterHotKey(hWnd: HWND, id: i32) callconv(.winapi) BOOL;
pub extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.winapi) i32;
pub extern "user32" fn OpenClipboard(hWndNewOwner: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn EmptyClipboard() callconv(.winapi) BOOL;
pub extern "user32" fn SetClipboardData(uFormat: UINT, hMem: HANDLE) callconv(.winapi) HANDLE;
pub extern "user32" fn CloseClipboard() callconv(.winapi) BOOL;
pub extern "user32" fn SendInput(cInputs: UINT, pInputs: [*]INPUT, cbSize: i32) callconv(.winapi) UINT;

pub extern "kernel32" fn GlobalAlloc(uFlags: UINT, dwBytes: usize) callconv(.winapi) HANDLE;
pub extern "kernel32" fn GlobalFree(hMem: HANDLE) callconv(.winapi) HANDLE;
pub extern "kernel32" fn GlobalLock(hMem: HANDLE) callconv(.winapi) ?*anyopaque;
pub extern "kernel32" fn GlobalUnlock(hMem: HANDLE) callconv(.winapi) BOOL;
