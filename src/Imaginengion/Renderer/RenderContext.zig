const VertexArray = @import("../VertexArrays/VertexArray.zig");
const Window = @import("../Windows/Window.zig");
const builtin = @import("builtin");
const Vec4f32 = @import("../Math/LinAlg.zig").Vec4f32;
const Tracy = @import("../Core/Tracy.zig");

const Impl = switch (builtin.os.tag) {
    .windows => @import("SDLContext.zig"),
    else => @import("UnsupportedContext.zig"),
};

const RenderContext = @This();

mImpl: Impl = .{},

pub fn Init(self: *RenderContext, window: *Window) void {
    self.mImpl.Init(window);
}
pub fn Deinit(self: *RenderContext, window: *Window) void {
    self.mImpl.Deinit(window);
}

pub fn BeginFrame(self: *RenderContext, window: *Window, clear_color: Vec4f32) bool {
    return self.mImpl.BeginFrame(window, clear_color);
}

pub fn GetMaxTextureImageSlots(self: RenderContext) usize {
    return self.mImpl.GetMaxTextureImageSlots();
}

pub fn GetDevice(self: RenderContext) *anyopaque {
    return self.mImpl.GetDevice();
}

pub fn GetRenderPass(self: RenderContext) *anyopaque {
    return self.mImpl.GetRenderPass();
}

pub fn GetCommandBuff(self: RenderContext) *anyopaque {
    return self.mImpl.GetCommandBuff();
}

pub fn Draw(self: RenderContext) void {
    self.mImpl.Draw();
}

pub fn PushDebugGroup(self: RenderContext, message: []const u8) void {
    self.mImpl.PushDebugGroup(message);
}

pub fn PopDebugGroup(self: RenderContext) void {
    self.mImpl.PopDebugGroup();
}
