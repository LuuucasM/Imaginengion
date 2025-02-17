const std = @import("std");
const nfd = @import("../Core/CImports.zig").nfd;
const PlatformUtils = @This();

pub fn OpenFolder(allocator: std.mem.Allocator) ![]const u8 {
    var outPath: [*c]nfd.nfdchar_t = undefined;
    const folder_result = nfd.NFD_PickFolder(null, &outPath);

    if (folder_result != nfd.NFD_OKAY) {
        if (folder_result == nfd.NFD_ERROR) {
            std.log.err("NFD Error: {s}\n", .{nfd.NFD_GetError()});
        }
        return &[_]u8{};
    }

    defer nfd.free(outPath);

    const len = std.mem.len(outPath);
    const path_result = try allocator.alloc(u8, len);

    @memcpy(path_result, outPath[0..len]);
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

    defer nfd.free(outPath);

    const path_len = std.mem.len(outPath);
    const path_result = try allocator.alloc(u8, path_len);

    @memcpy(path_result[0..path_len], outPath[0..path_len]);

    return path_result;
}

pub fn SaveFile(allocator: std.mem.Allocator, filter: [*c]const u8) ![]const u8 {
    var outPath: [*c]nfd.nfdchar_t = undefined;
    const file_result = nfd.NFD_SaveDialog(&filter[1], null, &outPath);

    if (file_result != nfd.NFD_OKAY) {
        if (file_result == nfd.NFD_ERROR) {
            std.log.err("NFD Error: {s}\n", .{nfd.NFD_GetError()});
        }
        return &[_]u8{};
    }

    defer nfd.free(outPath);

    const path_len = std.mem.len(outPath);
    const filter_len = std.mem.len(filter);

    const ext_slice = outPath[(path_len - filter_len)..path_len];
    if (std.mem.eql(u8, ext_slice, filter[0..filter_len]) == true) {
        const path_result = try allocator.alloc(u8, path_len);
        @memcpy(path_result, outPath[0..path_len]);
        return path_result;
    } else {
        const path_result = try allocator.alloc(u8, path_len + filter_len);
        @memcpy(path_result[0..path_len], outPath[0..path_len]);
        @memcpy(path_result[path_len..], filter[0..filter_len]);
        return path_result;
    }
}
