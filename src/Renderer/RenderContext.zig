const std = @import("std");
const builtin = @import("builtin");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLContext.zig"),
    else => @import("UnsupportedContext.zig"),
};

const RenderContext = @This();

_Impl: Impl,

pub fn Init() RenderContext {
    return RenderContext{
        ._Impl = Impl.Init(),
    };
}

pub fn SwapBuffers(self: RenderContext) void {
    self._Impl.SwapBuffers();
}
