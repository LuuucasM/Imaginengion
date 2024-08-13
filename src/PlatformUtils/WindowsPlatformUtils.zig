const Application = @import("../Core/Application.zig");
const glfw = @import("../Core/CImports.zig").glfw;
const windows = @import("../Core/CImports.zig").windows;

pub fn OpenFile(filter: []const u8) []const u8 {
    var ofn: windows.OPENFILENAMEA = std.mem.zeroes(windows.OPENFILENAMEA);
    const szFile: [256]windows.CHAR = std.mem.zeroes([256]windows.CHAR);
    const currentDir: [256]windows.CHAR = std.mem.zeroes([256]windows.CHAR);

    ofn.lStructSize = @sizeOf(windows.OPENFILENAMEA);
    ofn.hwndOwner = windows.glfwGetWin32Window(@as(*glfw.GLFWwindow, @ptrCast(Application.GetNativeWindow())));
    ofn.lpstrFile = szFile;
    ofn.nMaxFile = @sizeOf(szFile);
    if (windows.GetCurrentDirectoryA(256, currentDir) != 0) {
        ofn.lpstrInitialDir = currentDir;
    }
    ofn.lpstrFilter = filter;
    ofn.nFilterIndex = 1;
    ofn.Flags = windows.OFN_PATHMUSTEXIST | windows.OFN_FILEMUSTEXIST | windows.OFN_NOCHANGEDIR;
    if (windows.GetOpenFileNameA(&ofn) == windows.TRUE) {
        return ofn.lpstrFile;
    }
    return "";
}

pub fn SaveFile(filter: []const u8) []const u8 {
    var ofn: windows.OPENFILENAMEA = std.mem.zeroes(windows.OPENFILENAMEA);
    const szFile: [256]windows.CHAR = std.mem.zeroes([256]windows.CHAR);
    const currentDir: [256]windows.CHAR = std.mem.zeroes([256]windows.CHAR);

    ofn.lStructSize = @sizeOf(windows.OPENFILENAMEA);
    ofn.hwndOwner = windows.glfwGetWin32Window(@as(*glfw.GLFWwindow, @ptrCast(Application.GetNativeWindow())));
    ofn.lpstrFile = szFile;
    ofn.nMaxFile = @sizeOf(szFile);
    if (windows.GetCurrentDirectoryA(256, currentDir) != 0) {
        ofn.lpstrInitialDir = currentDir;
    }

    ofn.lpstrFilter = filter;
    ofn.nFilterIndex = 1;
    ofn.lpstrDefExt = std.mem.indexOf(u8, filter, '\0') + 1;

    ofn.Flags = windows.OFN_PATHMUSTEXIST | windows.OFN_OVERWRITEPROMPT | windows.OFN_NOCHANGEDIR;
    if (windows.GetSaveFileNameA(&ofn) == windows.TRUE) {
        return ofn.lpstrFile;
    }
    return "";
}
