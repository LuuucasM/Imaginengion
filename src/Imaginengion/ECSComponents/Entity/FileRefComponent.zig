const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const PathType = @import("../../ECSManagers/AManager.zig").PathType;
const FileRefComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "FileRefComponent";

/// The file an entity stands for, e.g. a file in the Content Browser: a drag source (DragSourceComponent) with one
/// carries the file, and a drop target that takes FileRefComponent reads which file was dropped. A path rather than an
/// asset handle, so showing a folder doesn't make an asset of every file in it. Set up by code, never saved
mRelPath: std.ArrayList(u8) = .empty,
mPathType: PathType = .Prj,

/// `keep_allocator` is the Keep of the object it goes on (Entity.Keep), which frees it
pub fn Init(keep_allocator: std.mem.Allocator, rel_path: []const u8, path_type: PathType) !FileRefComponent {
    var file_ref = FileRefComponent{ .mPathType = path_type };
    try file_ref.mRelPath.appendSlice(keep_allocator, rel_path);
    return file_ref;
}

pub fn Deinit(self: *FileRefComponent, _: *EngineContext, keep_allocator: std.mem.Allocator) void {
    self.mRelPath.deinit(keep_allocator);
}

pub fn Clone(self: *const FileRefComponent, _: *EngineContext, keep_allocator: std.mem.Allocator) !FileRefComponent {
    return .{ .mRelPath = try self.mRelPath.clone(keep_allocator), .mPathType = self.mPathType };
}
