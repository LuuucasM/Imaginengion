const std = @import("std");
const FrameBuffer = @This();

mPtr: *anyopaque,
mVTable: *const VTab,
mAllocator: std.mem.Allocator,

const VTab = struct {
    Deinit: *const fn (*anyopaque, std.mem.Allocator) void,
    Invalidate: *const fn (*anyopaque) void,
    Bind: *const fn (*anyopaque) void,
    Unbind: *const fn (*anyopaque) void,
    Resize: *const fn (*anyopaque, usize, usize) void,
    ClearColorAttachment: *const fn (*anyopaque, u8, u32) void,
    BindColorAttachment: *const fn (*anyopaque, u8, u32) void,
    BindDepthAttachment: *const fn (*anyopaque, u8, u32) void,
};

pub fn Init(allocator: std.mem.Allocator, comptime internal_type: type, width: usize, height: usize) !FrameBuffer {
    std.debug.assert(@typeInfo(internal_type) == .@"struct" and std.mem.startsWith(u8, @typeName(internal_type), "FrameBuffers.InternalFrameBuffer"));

    const impl = struct {
        fn Deinit(ptr: *anyopaque, deinit_allocator: std.mem.Allocator) void {
            const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
            self.Deinit();
            deinit_allocator.destroy(self);
        }
        fn Invalidate(ptr: *anyopaque) void {
            const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
            self.Invalidate();
        }
        fn Bind(ptr: *anyopaque) void {
            const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
            self.Bind();
        }
        fn Unbind(ptr: *anyopaque) void {
            const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
            self.Unbind();
        }
        fn Resize(ptr: *anyopaque, resize_width: usize, resize_height: usize) void {
            const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
            self.Resize(resize_width, resize_height);
        }
        fn ClearColorAttachment(ptr: *anyopaque, attachment_index: u8, value: u32) void {
            const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
            self.ClearColorAttachment(attachment_index, value);
        }
        fn BindColorAttachment(ptr: *anyopaque, attachment_index: u8, slot: u32) void {
            const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
            self.BindColorAttachment(attachment_index, slot);
        }
        fn BindDepthAttachment(ptr: *anyopaque, slot: u32) void {
            const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
            self.BindDepthAttachment(slot);
        }
    };

    const new_internal_fb = try allocator.create(internal_type);
    new_internal_fb.* = internal_type.Init(width, height);

    return FrameBuffer{
        .mPtr = new_internal_fb,
        .mVTable = &.{
            .Deinit = impl.Deinit,
            .Invalidate = impl.Invalidate,
            .Bind = impl.Bind,
            .Unbind = impl.Unbind,
            .Resize = impl.Resize,
            .ClearColorAttachment = impl.ClearColorAttachment,
            .BindColorAttachment = impl.BindColorAttachment,
            .BindDepthAttachment = impl.BindDepthAttachment,
        },
        .mAllocator = allocator,
    };
}

pub fn Deinit(self: FrameBuffer) void {
    self.mVTable.Deinit(self.mPtr, self.mAllocator);
}
pub fn Invalidate(self: FrameBuffer) void {
    self.mVTable.Invalidate(self.mPtr);
}
pub fn Bind(self: FrameBuffer) void {
    self.mVTable.Bind(self.mPtr);
}
pub fn Unbind(self: FrameBuffer) void {
    self.mVTable.Unbind(self.mPtr);
}
pub fn Resize(self: FrameBuffer, width: usize, height: usize) void {
    self.mVTable.Resize(self.mPtr, width, height);
}
pub fn ClearColorAttachment(self: FrameBuffer, attachment_index: u8, value: u32) void {
    self.mVTable.ClearColorAttachment(self.mPtr, attachment_index, value);
}
pub fn BindColorAttachment(self: FrameBuffer, attachment_index: u8, slot: u32) void {
    self.mVTable.BindColorAttachment(self.mPtr, attachment_index, slot);
}
pub fn BindDepthAttachment(self: FrameBuffer, slot: u32) void {
    self.mVTable.BindDepthAttachment(self.mPtr, slot);
}
