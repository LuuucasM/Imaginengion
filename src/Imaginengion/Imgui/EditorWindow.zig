const std = @import("std");
const Entity = @import("../GameObjects/Entity.zig");
const EditorWindow = @This();

mEntity: Entity,
mPtr: *anyopaque,
mVTable: *const VTab,

const VTab = struct {
    EditorRender: *const fn (*anyopaque, std.mem.Allocator) anyerror!void,
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
        fn EditorRender(ptr: *anyopaque, frame_allocator: std.mem.Allocator) !void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            try self.EditorRender(frame_allocator);
        }
        fn GetComponentName(ptr: *anyopaque) []const u8 {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return self.GetName();
        }

        fn GetComponentID(ptr: *anyopaque) u32 {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
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

pub fn EditorRender(self: EditorWindow, frame_allocator: std.mem.Allocator) !void {
    try self.mVTable.EditorRender(self.mPtr, frame_allocator);
}

pub fn GetComponentName(self: EditorWindow) []const u8 {
    return self.mVTable.GetComponentName(self.mPtr);
}

pub fn GetComponentID(self: EditorWindow) u32 {
    return self.mVTable.GetComponentID(self.mPtr);
}
