const std = @import("std");
const builtin = @import("builtin");
const EngineContext = @import("../Core/EngineContext.zig");
const Stage = @import("../Assets/Assets.zig").ShaderAsset.Stage;
const SSBO = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("SDLGPUSSBO.zig"),
    else => @compileError("This shouldnt happne"),
};

mImpl: Impl = .empty,

pub fn Init(self: *SSBO, engine_context: *EngineContext, size: usize, slot: usize, stage: Stage) void {
    self.mImpl.Init(engine_context, size, slot, stage);
}

pub fn Deinit(self: *SSBO, engine_context: *EngineContext) void {
    self.mImpl.Deinit(engine_context);
}

pub fn Bind(self: SSBO, render_pass: *anyopaque) void {
    self.mImpl.Bind(render_pass);
}

pub fn Unbind(self: SSBO) void {
    self.mImpl.Unbind();
}

pub fn SetData(self: *SSBO, engine_context: *EngineContext, data: *anyopaque, size: usize, offset: u32) bool {
    return self.mImpl.SetData(engine_context, data, size, offset);
}

pub fn GetBuffer(self: SSBO) *anyopaque {
    return self.mImpl.GetBuffer();
}

pub fn GetBinding(self: SSBO) usize {
    return self.mImpl.GetBinding();
}
