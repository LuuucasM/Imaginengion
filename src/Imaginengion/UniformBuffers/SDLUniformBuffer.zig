const sdl = @import("../Core/CImports.zig").sdl;
const SDLUniformBuffer = @This();
const EngineContext = @import("../Core/EngineContext.zig");
const Stage = @import("../Assets/Assets/ShaderAsset.zig").Stage;

mSlot: u32 = 0,
mStage: Stage,

pub const empty: SDLUniformBuffer = .{
    .mSlot = undefined,
    .mStage = undefined,
};

pub fn Init(self: *SDLUniformBuffer, slot: u32, stage: Stage) void {
    self.mSlot = slot;
    self.mStage = stage;
}

pub fn SetData(self: SDLUniformBuffer, engine_context: *EngineContext, data: *const anyopaque, size: u32) void {
    const cmd: *sdl.SDL_GPUCommandBuffer = @ptrCast(@alignCast(engine_context.mRenderer.mRenderContext.GetCommandBuff()));

    switch (self.mStage) {
        .vertex => sdl.SDL_PushGPUVertexUniformData(cmd, self.mSlot, data, size),
        .fragment => sdl.SDL_PushGPUFragmentUniformData(cmd, self.mSlot, data, size),
    }
}
