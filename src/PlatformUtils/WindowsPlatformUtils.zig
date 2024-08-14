const std = @import("std");
const windowsI = @import("../Core/CImports.zig").windows;
const windows = std.os.windows;
//const PCIDLIST_ABSOLUTE = w;
const LPSTR = windows.LPSTR;
const UINT = windows.UINT;
const WINAPI = windows.WINAPI;
const HWND = windows.HWND;
const DWORD = windows.DWORD;
const LPARAM = windows.LPARAM;
const LPCWSTR = windows.LPCWSTR;
const LPVOID = windows.LPVOID;

const MAX_PATH = 260;

const BROWSEINFO = extern struct {
    hwndOwner: HWND,
    pidlRoot: LPVOID,
    pszDisplayName: LPSTR,
    lpszTitle: LPCWSTR,
    ulFlags: UINT,
    lpfn: *const BFFCALLBACK,
    lParam: LPARAM,
    iImage: c_int,
};

const BFFCALLBACK = fn (hwnd: HWND, uMsg: DWORD, lParam: LPARAM, lpData: LPARAM) callconv(WINAPI) i32;

pub fn OpenFolder() ![]const u8 {
    var bi = std.mem.zeroes(BROWSEINFO);
    bi.lpszTitle = std.unicode.utf8ToUtf16LeStringLiteral("Select a folder");
    bi.ulFlags = windowsI.BIF_NEWDIALOGSTYLE | windowsI.BIF_RETURNONLYFSDIRS | windowsI.BIF_EDITBOX | windowsI.BIF_USENEWUI; // BIF_NEWDIALOGSTYLE | BIF_RETURNONLYFSDIRS
    //std.debug.print("the value of flags: {}\n", .{bi.ulFlags});
    const pidl = windowsI.SHBrowseForFolderW(@ptrCast(&bi)) orelse {
        std.debug.print("No folder selected\n", .{});
        return "";
    };
    defer windowsI.CoTaskMemFree(pidl);

    var path: [MAX_PATH:0]u16 = undefined;
    if (windowsI.SHGetPathFromIDListW(pidl, &path) == 0) {
        return "";
    }

    const len = std.mem.indexOfScalar(u16, &path, 0) orelse MAX_PATH;
    const allocator = std.heap.page_allocator;

    return try std.unicode.utf16leToUtf8Alloc(allocator, path[0..len]);
}
