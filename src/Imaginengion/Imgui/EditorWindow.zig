const std = @import("std");
const Entity = @import("../GameObjects/Entity.zig");
const EditorWindow = @This();

mEntity: Entity,
mPtr: *anyopaque,
mVTable: *const VTab,

const VTab = struct {
    EditorRender: *const fn (*anyopaque) anyerror!void,
    GetComponentName: *const fn (*anyopaque) []const u8,
    GetComponentID: *const fn (*anyopaque) u32,
};

pub fn Init(obj: anytype, entity: Entity) EditorWindow {
    const Ptr = @TypeOf(obj);
    const PtrInfo = @typeInfo(Ptr);
    std.debug.assert(PtrInfo == .pointer);
    std.debug.assert(PtrInfo.pointer.size == .one);
    std.debug.assert(@typeInfo(PtrInfo.pointer.child) == .@"struct");

    const impl = struct {
        fn EditorRender(ptr: *anyopaque) !void {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            try self.EditorRender();
        }
        fn GetComponentName(ptr: *anyopaque) []const u8 {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            return self.GetName();
        }

        fn GetComponentID(ptr: *anyopaque) u32 {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            return @intCast(self.GetInd());
        }
    };

    return EditorWindow{
        .mEntity = entity,
        .mPtr = obj,
        .mVTable = &.{
            .EditorRender = impl.EditorRender,
            .GetComponentName = impl.GetComponentName,
            .GetComponentID = impl.GetComponentID,
        },
    };
}

pub fn EditorRender(self: EditorWindow) !void {
    try self.mVTable.EditorRender(self.mPtr);
}

pub fn GetComponentName(self: EditorWindow) []const u8 {
    return self.mVTable.GetComponentName(self.mPtr);
}

pub fn GetComponentID(self: EditorWindow) u32 {
    return self.mVTable.GetComponentID(self.mPtr);
}
