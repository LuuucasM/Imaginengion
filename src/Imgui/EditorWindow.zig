const std = @import("std");
const EditorWindow = @This();

Ptr: *anyopaque,
VTable: VTab,

const VTab = struct {
    ImguiRender: *const fn (*anyopaque) void,
};

pub fn Init(obj: anytype) EditorWindow {
    const Ptr = @TypeOf(obj);
    const PtrInfo = @typeInfo(Ptr);
    std.debug.assert(PtrInfo == .pointer);
    std.debug.assert(PtrInfo.pointer.size == .One);
    std.debug.assert(@typeInfo(PtrInfo.pointer.child) == .@"struct");

    const impl = struct {
        fn ImguiRender(ptr: *anyopaque) void {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            self.ImguiRender();
        }
    };

    return EditorWindow{
        .Ptr = obj,
        .VTable = &.{
            .ImguiRender = impl.ImguiRender,
        },
    };
}

pub fn ImguiRender(self: EditorWindow) void {
    self.VTable.ImguiRender(self.Ptr);
}
