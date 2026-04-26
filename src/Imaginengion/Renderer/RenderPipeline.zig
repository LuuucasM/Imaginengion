const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("../Core/CImports.zig").sdl;
const ShaderAsset = @import("../Assets/Assets.zig").ShaderAsset;
const TextureFormat = @import("../Assets/Assets.zig").Texture2D.TextureFormat;
const EngineContext = @import("../Core/EngineContext.zig");

pub const PushConstants = switch (builtin.os.tag) {
    .windows => @import("backends/SDLGPUPipeline.zig").PushConstants,
    else => @compileError("not supported currently!\n"),
};

pub const PipelineConfig = struct {
    color_format: TextureFormat,
    enable_blend: bool = true,
};

comptime {
    std.debug.assert(@sizeOf(PushConstants) <= 128);
}

const Impl = switch (builtin.os.tag) {
    .windows => @import("backends/SDLGPUPipeline.zig"),
    else => @compileError("not suported currently!\n"),
};

const RenderPipeline = @This();

_Impl: Impl = .{},

pub fn Init(self: *RenderPipeline, engine_context: *EngineContext, shader: *ShaderAsset, config: PipelineConfig) !void {
    self._Impl.Init(engine_context, shader, config);
}

pub fn Deinit(self: *RenderPipeline, engine_context: *EngineContext) void {
    self._Impl.Deinit(engine_context);
}

pub fn Bind(self: RenderPipeline, render_pass: *anyopaque) void {
    self._Impl.Bind(render_pass);
}

pub fn PushUniforms(self: RenderPipeline, cmd: *anyopaque, push: PushConstants) void {
    self._Impl.PushUniforms(cmd, push);
}

pub fn Draw(self: RenderPipeline, render_pass: *anyopaque) void {
    self._Impl.Draw(render_pass);
}
