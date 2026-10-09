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

pub fn Init(engine_context: *EngineContext, rel_path: []const u8, path_type: PathType) !FileRefComponent {
    var file_ref = FileRefComponent{ .mPathType = path_type };
    try file_ref.mRelPath.appendSlice(engine_context.EngineAllocator(), rel_path);
    return file_ref;
}

pub fn Deinit(self: *FileRefComponent, engine_context: *EngineContext) void {
    self.mRelPath.deinit(engine_context.EngineAllocator());
}

pub fn Clone(self: *const FileRefComponent, engine_context: *EngineContext) !FileRefComponent {
    return .{ .mRelPath = try self.mRelPath.clone(engine_context.EngineAllocator()), .mPathType = self.mPathType };
}
