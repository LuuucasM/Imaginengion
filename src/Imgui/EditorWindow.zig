const std = @import("std");
const Entity = @import("../ECS/Entity.zig");
const EditorWindow = @This();

mAssetID: u32,
mPtr: *anyopaque,
mVTable: *const VTab,

const VTab = struct {
    EditorRender: *const fn (*anyopaque) anyerror!void,
    GetComponentName: *const fn (*anyopaque) []const u8,
};

pub fn Init(obj: anytype, asset_id: u32) EditorWindow {
    const Ptr = @TypeOf(obj);
    const PtrInfo = @typeInfo(Ptr);
    std.debug.assert(PtrInfo == .Pointer);
    std.debug.assert(PtrInfo.Pointer.size == .One);
    std.debug.assert(@typeInfo(PtrInfo.Pointer.child) == .Struct);

    const impl = struct {
        fn EditorRender(ptr: *anyopaque) !void {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            try self.EditorRender();
        }
        fn GetComponentName(ptr: *anyopaque) []const u8 {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            return self.GetName();
        }
    };

    return EditorWindow{
        .mAssetID = asset_id,
        .mPtr = obj,
        .mVTable = &.{
            .EditorRender = impl.EditorRender,
            .GetComponentName = impl.GetComponentName,
        },
    };
}

pub fn EditorRender(self: EditorWindow) !void {
    try self.mVTable.EditorRender(self.mPtr);
}

pub fn GetComponentName(self: EditorWindow) []const u8 {
    return self.mVTable.GetComponentName(self.mPtr);
}
