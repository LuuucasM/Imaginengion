const std = @import("std");
const Entity = @import("../ECS/Entity.zig");
const EditorWindow = @This();

mAssetID: u32,
mPtr: *anyopaque,
mVTable: VTab,

const VTab = struct {
    EditorRender: *const fn (*anyopaque) void,
};

pub fn Init(obj: anytype, asset_id: u32) EditorWindow {
    const Ptr = @TypeOf(obj);
    const PtrInfo = @typeInfo(Ptr);
    std.debug.assert(PtrInfo == .pointer);
    std.debug.assert(PtrInfo.pointer.size == .One);
    std.debug.assert(@typeInfo(PtrInfo.pointer.child) == .@"struct");

    const impl = struct {
        fn EditorRender(ptr: *anyopaque) void {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            self.EditorRender();
        }
    };

    return EditorWindow{
        .mAssetID = asset_id,
        .mPtr = obj,
        .mVTable = &.{
            .EditorRender = impl.EditorRender,
        },
    };
}

pub fn EditorRender(self: EditorWindow) void {
    self.VTable.EditorRender(self.Ptr);
}
