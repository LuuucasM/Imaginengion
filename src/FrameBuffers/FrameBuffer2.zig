const std = @import("std");
const FrameBuffer = @This();

mPtr: *anyopaque,
mVTable: *const VTab,

const VTab = struct {
    Deinit: *const fn (*anyopaque) void,
    Invalidate: *const fn (*anyopaque) void,
    Bind: *const fn (*anyopaque) void,
    Unbind: *const fn (*anyopaque) void,
    Resize: *const fn (*anyopaque, usize, usize) void,
    ClearColorAttachment: *const fn (*anyopaque, u8, u32) void,
};

pub fn Init(obj: anytype) FrameBuffer {
    const Ptr = @TypeOf(obj);
    const PtrInfo = @typeInfo(Ptr);
    std.debug.assert(PtrInfo == .pointer);
    std.debug.assert(PtrInfo.pointer.size == .one);
    std.debug.assert(@typeInfo(PtrInfo.pointer.child) == .@"struct");

    const impl = struct {
        fn Deinit(ptr: *anyopaque) void {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            self.Deinit();
        }
        fn Invalidate(ptr: *anyopaque) void {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            self.Invalidate();
        }
        fn Bind(ptr: *anyopaque) void {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            self.Bind();
        }
        fn Unbind(ptr: *anyopaque) void {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            self.Unbind();
        }
        fn Resize(ptr: *anyopaque, width: usize, height: usize) void {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            self.Resize(width, height);
        }
        fn ClearColorAttachment(ptr: *anyopaque, attachment_index: u8, value: u32) void {
            const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
            self.ClearColorAttachment(attachment_index, value);
        }
    };

    return FrameBuffer{
        .mPtr = obj,
        .mVTable = &.{
            .Deinit = impl.Deinit,
            .Invalidate = impl.Invalidate,
            .Bind = impl.Bind,
            .Unbind = impl.Unbind,
            .Resize = impl.Resize,
            .ClearColorAttachment = impl.ClearColorAttachment,
        },
    };
}
