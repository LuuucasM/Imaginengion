const std = @import("std");
const Application = @import("../Core/Application.zig");
const glfw = @import("../Core/CImports.zig").glfw;
const nativeos = @import("../Core/CImports.zig").nativeos;
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
const CHAR = windows.CHAR;

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
    bi.ulFlags = nativeos.BIF_NEWDIALOGSTYLE | nativeos.BIF_RETURNONLYFSDIRS | nativeos.BIF_EDITBOX | nativeos.BIF_USENEWUI; // BIF_NEWDIALOGSTYLE | BIF_RETURNONLYFSDIRS
    const pidl = nativeos.SHBrowseForFolderW(@ptrCast(&bi)) orelse {
        std.debug.print("No folder selected\n", .{});
        return "";
    };
    defer nativeos.CoTaskMemFree(pidl);

    var path: [MAX_PATH:0]u16 = undefined;
    if (nativeos.SHGetPathFromIDListW(pidl, &path) == 0) {
        return "";
    }

    const len = std.mem.indexOfScalar(u16, &path, 0) orelse MAX_PATH;
    const allocator = std.heap.page_allocator;

    return try std.unicode.utf16leToUtf8Alloc(allocator, path[0..len]);
}

pub fn OpenFile(filter: []const u8) ![]const u8{
    var ofn: nativeos.OPENFILENAMEA = std.mem.zeroes(nativeos.OPENFILENAMEA);
    var szFile: [260]CHAR = std.mem.zeroes([260]CHAR);
    var currentDir: [260]CHAR = std.mem.zeroes([260]CHAR);
    ofn.lStructSize = @sizeOf(nativeos.OPENFILENAMEA);
    ofn.hwndOwner = nativeos.glfwGetWin32Window(@ptrCast(Application.GetNativeWindow()));
    ofn.lpstrFile = @ptrCast(&szFile);
    ofn.nMaxFile = @sizeOf(CHAR)*260;
    if (nativeos.GetCurrentDirectoryA(260, @ptrCast(&currentDir)) != 0){
        ofn.lpstrInitialDir = @ptrCast(&currentDir);
    }
    ofn.lpstrFilter = @ptrCast(filter);
    ofn.nFilterIndex = 1;
    ofn.Flags = nativeos.OFN_PATHMUSTEXIST | nativeos.OFN_FILEMUSTEXIST | nativeos.OFN_NOCHANGEDIR;
    if (nativeos.GetOpenFileNameA(&ofn) == nativeos.TRUE){
        const len = std.mem.len(ofn.lpstrFile);
        return ofn.lpstrFile[0..len];
    }
    return "";
}