/// file: NFDUtils.zig
///
/// Provides thin wrappers around nativefiledialog (NFD) usage for file/folder selection
/// in a Zig application. Each function handles memory allocation for the resulting path,
/// and returns an empty slice on user cancellation. The user is responsible for
/// eventually freeing the returned slice.

const std = @import("std");
const nfd = @import("../Core/CImports.zig").nfd;

/// Attempt to open a folder via the NFD pick-folder dialog.
///
/// On success, returns a newly allocated slice containing the folder path.
/// On cancellation or error, returns an empty slice.
/// An error is thrown only if allocation fails or if NFD signals an internal error.
pub fn openFolder(allocator: std.mem.Allocator) ![]const u8 {
    var outPtr: [*c]nfd.nfdchar_t = undefined;
    const resultCode = nfd.NFD_PickFolder(null, &outPtr);

    defer if (outPtr != null) nfd.free(outPtr);

    switch (resultCode) {
        nfd.NFD_OKAY => {},
        nfd.NFD_CANCEL => return &[_]u8{},
        nfd.NFD_ERROR => {
            std.log.err("NFD Error: {s}", .{ nfd.NFD_GetError() });
            return &[_]u8{};
        },
        else => return &[_]u8{},
    }

    const rawLen = std.mem.len(outPtr);
    const outSlice = try allocator.alloc(u8, rawLen);
    std.mem.copy(u8, outSlice, outPtr[0..rawLen]);

    return outSlice;
}

/// Attempt to open a file using the NFD open-dialog with an optional filter string
/// (like "png,jpg" or "txt").
///
/// On success, returns an allocated slice containing the file path.
/// On cancellation or error, returns an empty slice.
pub fn openFile(allocator: std.mem.Allocator, filter: [*c]const u8) ![]const u8 {
    var outPtr: [*c]nfd.nfdchar_t = undefined;
    const resultCode = nfd.NFD_OpenDialog(&filter[1], null, &outPtr);

    defer if (outPtr != null) nfd.free(outPtr);

    switch (resultCode) {
        nfd.NFD_OKAY => {},
        nfd.NFD_CANCEL => return &[_]u8{},
        nfd.NFD_ERROR => {
            std.log.err("NFD Error: {s}", .{ nfd.NFD_GetError() });
            return &[_]u8{};
        },
        else => return &[_]u8{},
    }

    const rawLen = std.mem.len(outPtr);
    const outSlice = try allocator.alloc(u8, rawLen);
    std.mem.copy(u8, outSlice, outPtr[0..rawLen]);

    return outSlice;
}

/// Attempt to save a file via NFD. This uses NFD_SaveDialog; if user
/// doesn't provide the matching extension from `filter`, the extension is appended.
///
/// The `filter` param is typically something like ".txt" or ".png".
/// Returns an allocated slice with the full path, or an empty slice on cancellation/error.
pub fn saveFile(allocator: std.mem.Allocator, filter: [*c]const u8) ![]const u8 {
    var outPtr: [*c]nfd.nfdchar_t = undefined;
    const resultCode = nfd.NFD_SaveDialog(&filter[1], null, &outPtr);

    defer if (outPtr != null) nfd.free(outPtr);

    switch (resultCode) {
        nfd.NFD_OKAY => {},
        nfd.NFD_CANCEL => return &[_]u8{},
        nfd.NFD_ERROR => {
            std.log.err("NFD Error: {s}", .{ nfd.NFD_GetError() });
            return &[_]u8{};
        },
        else => return &[_]u8{},
    }

    const rawLen = std.mem.len(outPtr);
    const filterLen = std.mem.len(filter);

    // Check if the chosen path ends with the desired extension (filter).
    if (rawLen >= filterLen) {
        // Compare last N bytes with the extension.
        const extSlice = outPtr[(rawLen - filterLen)..rawLen];
        if (std.mem.eql(u8, extSlice, filter)) {
            // Already has the extension
            const outSlice = try allocator.alloc(u8, rawLen);
            std.mem.copy(u8, outSlice, outPtr[0..rawLen]);
            return outSlice;
        }
    }

    // If we get here, the extension is missing. Append it.
    const outSlice = try allocator.alloc(u8, rawLen + filterLen);
    std.mem.copy(u8, outSlice[0..rawLen], outPtr[0..rawLen]);
    std.mem.copy(u8, outSlice[rawLen..], filter[0..filterLen]);

    return outSlice;
}

