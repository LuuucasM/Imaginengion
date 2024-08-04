const std = @import("std");
const builtin = @import("builtin");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLContext.zig"),
    else => @import("UnsupportedContext.zig"),
};

const RenderContext = @This();

_Impl: Impl,
_EngineAllocator: std.mem.Allocator,

pub fn Init(EngineAllocator: std.mem.Allocator) !*RenderContext {
    const ptr = try EngineAllocator.create(RenderContext);
    ptr.* = .{
        ._Impl = .{},
        ._EngineAllocator = EngineAllocator,
    };
    ptr._Impl.Init();
    return ptr;
}
pub fn Deinit(self: *RenderContext) void {
    self._EngineAllocator.destroy(self);
}

pub fn SwapBuffers(self: RenderContext) void {
    self._Impl.SwapBuffers();
}
