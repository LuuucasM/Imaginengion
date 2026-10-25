const std = @import("std");
const builtin = @import("builtin");
const nfd = @import("../Core/CImports.zig").nfd;
const windows = std.os.windows;
const PlatformUtils = @This();

/// The part of a stat the asset manager compares to tell whether a file changed
pub const FileTimeAndSize = struct {
    mtime: std.Io.Timestamp,
    size: u64,
};

/// mtime and size of the file at `sub_path` in `dir`. On Windows a full stat opens a handle, queries
/// it, and closes it, and the open is most of the cost, so this asks by path in one call instead.
/// Elsewhere a stat by path is already one call with no handle, so it is just a stat
pub fn StatTimeAndSize(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !FileTimeAndSize {
    if (builtin.os.tag == .windows) return StatTimeAndSizeWindows(dir, sub_path);
    const stat = try dir.statFile(io, sub_path, .{});
    return .{ .mtime = stat.mtime, .size = stat.size };
}

fn StatTimeAndSizeWindows(dir: std.Io.Dir, sub_path: []const u8) !FileTimeAndSize {
    //the same path conversion std's own Windows open uses: WTF-16, '/' to '\', '.' and '..' resolved
    const sub_path_w = try std.Io.Threaded.sliceToPrefixedFileW(dir.handle, sub_path, .{});
    const attr: windows.OBJECT.ATTRIBUTES = .{
        .RootDirectory = if (std.fs.path.isAbsoluteWindowsWtf16(sub_path_w.span())) null else dir.handle,
        .ObjectName = @constCast(&sub_path_w.string()),
    };
    var info: FILE_NETWORK_OPEN_INFORMATION = undefined;
    return switch (NtQueryFullAttributesFile(&attr, &info)) {
        .SUCCESS => .{ .mtime = windows.fromSysTime(info.LastWriteTime), .size = @bitCast(info.EndOfFile) },
        .OBJECT_NAME_NOT_FOUND, .OBJECT_PATH_NOT_FOUND => error.FileNotFound,
        .ACCESS_DENIED => error.AccessDenied,
        .OBJECT_NAME_INVALID, .OBJECT_PATH_SYNTAX_BAD => error.BadPathName,
        else => |status| windows.unexpectedStatus(status),
    };
}

//not bound by std, which only has NtQueryAttributesFile (times and attributes, no size)
const FILE_NETWORK_OPEN_INFORMATION = extern struct {
    CreationTime: windows.LARGE_INTEGER,
    LastAccessTime: windows.LARGE_INTEGER,
    LastWriteTime: windows.LARGE_INTEGER,
    ChangeTime: windows.LARGE_INTEGER,
    AllocationSize: windows.LARGE_INTEGER,
    EndOfFile: windows.LARGE_INTEGER,
    FileAttributes: windows.ULONG,
};

extern "ntdll" fn NtQueryFullAttributesFile(
    ObjectAttributes: *const windows.OBJECT.ATTRIBUTES,
    FileInformation: *FILE_NETWORK_OPEN_INFORMATION,
) callconv(.winapi) windows.NTSTATUS;

pub fn OpenFolder(allocator: std.mem.Allocator) ![]const u8 {
    var outPath: [*c]nfd.nfdchar_t = undefined;
    const folder_result = nfd.NFD_PickFolder(null, &outPath);

    if (folder_result != nfd.NFD_OKAY) {
        if (folder_result == nfd.NFD_ERROR) {
            std.log.err("NFD Error: {s}\n", .{nfd.NFD_GetError()});
        }
        return &[_]u8{};
    }

    const len = std.mem.len(outPath);
    const path_result = try allocator.alloc(u8, len);

    @memcpy(path_result, outPath[0..len]);
    std.c.free(outPath);
    return path_result;
}

pub fn OpenFile(allocator: std.mem.Allocator, filter: [*c]const u8) ![]const u8 {
    var outPath: [*c]nfd.nfdchar_t = undefined;
    const file_result = nfd.NFD_OpenDialog(&filter[1], null, &outPath);

    if (file_result != nfd.NFD_OKAY) {
        if (file_result == nfd.NFD_ERROR) {
            std.log.err("NFD Error: {s}\n", .{nfd.NFD_GetError()});
        }
        return &[_]u8{};
    }

    const path_len = std.mem.len(outPath);
    const path_result = try allocator.alloc(u8, path_len);

    @memcpy(path_result[0..path_len], outPath[0..path_len]);
    std.c.free(outPath);

    return path_result;
}

/// `default_folder` is the folder the dialog opens in, null for the system's choice
pub fn SaveFile(allocator: std.mem.Allocator, filter: [*c]const u8, default_folder: ?[]const u8) ![]const u8 {
    //the native separator, as Windows' dialog can't open a folder written with '/'
    const folder: ?[:0]u8 = if (default_folder) |path| try allocator.dupeSentinel(u8, path, 0) else null;
    defer if (folder) |path| allocator.free(path);
    if (folder) |path| std.mem.replaceScalar(u8, path, if (std.fs.path.sep == '/') '\\' else '/', std.fs.path.sep);

    var outPath: [*c]nfd.nfdchar_t = undefined;
    const file_result = nfd.NFD_SaveDialog(&filter[1], if (folder) |path| path.ptr else null, &outPath);

    if (file_result != nfd.NFD_OKAY) {
        if (file_result == nfd.NFD_ERROR) {
            std.log.err("NFD Error: {s}\n", .{nfd.NFD_GetError()});
        }
        return &[_]u8{};
    }

    const path_len = std.mem.len(outPath);
    const filter_len = std.mem.len(filter);

    const ext_slice = outPath[(path_len - filter_len)..path_len];
    if (std.mem.eql(u8, ext_slice, filter[0..filter_len]) == true) {
        const path_result = try allocator.alloc(u8, path_len);
        @memcpy(path_result, outPath[0..path_len]);
        std.c.free(outPath);
        return path_result;
    } else {
        const path_result = try allocator.alloc(u8, path_len + filter_len);
        @memcpy(path_result[0..path_len], outPath[0..path_len]);
        @memcpy(path_result[path_len..], filter[0..filter_len]);
        std.c.free(outPath);
        return path_result;
    }
}
