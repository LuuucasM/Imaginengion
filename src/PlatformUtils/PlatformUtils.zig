const std = @import("std");
const nfd = @import("../Core/CImports.zig").nfd;
const PlatformUtils = @This();

pub fn OpenFolder(allocator: std.mem.Allocator) ![]const u8 {
    var outPath: [*c]nfd.nfdchar_t = undefined;

    const folder_result = nfd.NDF_PickFolder(null, &outPath);

    if (folder_result != nfd.NFD_OKAY){
        if (folder_result == nfd.NFD_ERROR){
            std.log.err("NFD Error: {s}\n", .{nfd.NFD_GetError()});
        }
        return "";
    }

    defer nfd.free(outPath);

    const len = std.mem.len(outPath);
    const path_result = try allocator.alloc(u8, len);

    @memcpy(path_result, outPath[0..len]);
    return path_result;
}

pub fn OpenFile(allocator: std.mem.Allocator, filter: [*c]const u8) ![]const u8 {
    var outPath: [*c]nfd.nfdchar_t = undefined;

    const folder_result = nfd.NFD_OpenDialog(filter, null, &outPath);

    if (folder_result != nfd.NFD_OKAY){
        if (folder_result == nfd.NFD_ERROR){
            std.log.err("NFD Error: {s}\n", .{nfd.NFD_GetError()});
        }
        return "";
    }

    defer nfd.free(outPath);

    const len = std.mem.len(outPath);
    const path_result = try allocator.alloc(u8, len);

    @memcpy(path_result, outPath[0..len]);
    return path_result;
}

pub fn SaveFile(allocator: std.mem.Allocator, filter: [*c]const u8) ![]const u8 {
    var outPath: [*c]nfd.nfdchar_t = undefined;

    const folder_result = nfd.NFD_OpenDialog(filter, null, &outPath);

    if (folder_result != nfd.NFD_OKAY){
        if (folder_result == nfd.NFD_ERROR){
            std.log.err("NFD Error: {s}\n", .{nfd.NFD_GetError()});
        }
        return "";
    }

    defer nfd.free(outPath);

    const len = std.mem.len(outPath);
    const path_result = try allocator.alloc(u8, len);

    @memcpy(path_result, outPath[0..len]);
    return path_result;
}
