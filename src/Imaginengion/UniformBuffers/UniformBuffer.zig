const builtin = @import("builtin");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Stage = @import("../Assets/Assets/ShaderAsset.zig").Stage;

const Impl = switch (builtin.os.tag) {
    .windows => @import("SDLUniformBuffer.zig"),
    else => @import("UnsupportedUniformBuffer.zig"),
};

const UniformBuffer = @This();

mImpl: Impl = .empty,

pub const empty: UniformBuffer = .{
    .mImpl = .empty,
};

pub fn Init(self: *UniformBuffer, slot: u32, stage: Stage) void {
    self.mImpl.Init(slot, stage);
}

pub fn SetData(self: UniformBuffer, engine_context: *EngineContext, data: *const anyopaque, size: u32) void {
    self.mImpl.SetData(engine_context, data, size);
}
