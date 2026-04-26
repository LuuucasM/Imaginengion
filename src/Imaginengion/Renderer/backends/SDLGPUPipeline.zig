const std = @import("std");
const sdl = @import("../../Core/CImports.zig").sdl;
const StorageBufferBinding = @import("../RenderPlatform.zig").StorageBufferBinding;
const PipelineConfig = @import("../RenderPipeline.zig").PipelineConfig;
const EngineContext = @import("../../Core/EngineContext.zig");
const ShaderAsset = @import("../../Assets/Assets.zig").ShaderAsset;
const StageInfo = ShaderAsset.StageInfo;
const Stage = ShaderAsset.Stage;
const TextureFormat = @import("../../Assets/Assets.zig").Texture2D.TextureFormat;

const SDLGPUPipeline = @This();

pub const PushConstants = extern struct {
    rotation: [4]f32, // 16 bytes
    position: [3]f32, // 12 bytes
    perspective_far: f32, //  4 bytes  → 32
    resolution_width: f32, //  4 bytes
    resolution_height: f32, //  4 bytes
    aspect_ratio: f32, //  4 bytes
    fov: f32, //  4 bytes  → 48
    mode: u32, //  4 bytes  → 52
    quads_count: u32, //  4 bytes  → 56
    glyphs_count: u32, //  4 bytes  → 60
};

mPipeline: ?*sdl.SDL_GPUGraphicsPipeline = null,

pub fn Init(self: *SDLGPUPipeline, engine_context: *EngineContext, shader: *ShaderAsset, config: PipelineConfig) !void {
    const device: *sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());

    const vert_shader = CreateShaderStage(device, shader.mShaderSources.mVertexBinary, shader.mShaderSources.mVertexStageInfo) orelse return error.AssetInitFailed;
    defer sdl.SDL_ReleaseGPUShader(device, vert_shader);

    const frag_shader = CreateShaderStage(device, shader.mShaderSources.mFragmentBinary, shader.mShaderSources.mFragmentStageInfo) orelse return error.AssetInitFailed;
    defer sdl.SDL_ReleaseGPUShader(device, frag_shader);

    self.mPipeline = try CreatePipeline(device, vert_shader, frag_shader, config);
    std.log.info("SDLGPUPipeline: created successfully", .{});
}

pub fn Deinit(self: *SDLGPUPipeline, engine_context: *EngineContext) void {
    const device: *sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());
    sdl.SDL_WaitForGPUIdle(device);
    if (self.mPipeline) |p| sdl.SDL_ReleaseGPUGraphicsPipeline(device, p);
    self.mPipeline = null;
}

pub fn Bind(self: SDLGPUPipeline, render_pass: *anyopaque) void {
    const sdl_render_pass: *sdl.SDL_GPURenderPass = @ptrCast(render_pass);

    sdl.SDL_BindGPUGraphicsPipeline(sdl_render_pass, self.mPipeline);
}

pub fn PushUniforms(_: SDLGPUPipeline, cmd: *anyopaque, push: PushConstants) void {
    const sdl_cmd: *sdl.SDL_GPUCommandBuffer = @ptrCast(cmd);

    sdl.SDL_PushGPUFragmentUniformData(
        sdl_cmd,
        0, // slot 0 — matches layout(push_constant) in the shader
        &push,
        @sizeOf(PushConstants),
    );
}

pub fn Draw(_: SDLGPUPipeline, render_pass: *anyopaque) void {
    const sdl_render_pass: *sdl.SDL_GPURenderPass = @ptrCast(render_pass);
    sdl.SDL_DrawGPUPrimitives(sdl_render_pass, 3, 1, 0, 0);
}

fn CreateShaderStage(device: *sdl.SDL_GPUDevice, code: []const u8, info: StageInfo) ?*sdl.SDL_GPUShader {
    std.debug.assert(code.len % 4 == 0);
    const create_info = sdl.SDL_GPUShaderCreateInfo{
        .code_size = code.len,
        .code = code.ptr,
        .entrypoint = "main",
        .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = ToSDLStage(info.mStage),
        .num_samplers = info.mNumSamplers,
        .num_storage_textures = 0,
        .num_storage_buffers = info.mNumStorageBuffers,
        .num_uniform_buffers = info.mNumUniformBuffers,
    };

    const shader = sdl.SDL_CreateGPUShader(device, &create_info);
    if (shader == null) {
        std.log.err("SDLGPUPipeline: failed to create shader stage — {s}", .{sdl.SDL_GetError()});
    }
    return shader;
}

fn CreatePipeline(device: *sdl.SDL_GPUDevice, vert_shader: *sdl.SDL_GPUShader, frag_shader: *sdl.SDL_GPUShader, config: PipelineConfig) !*sdl.SDL_GPUGraphicsPipeline {
    const blend_state = sdl.SDL_GPUColorTargetBlendState{
        .enable_blend = config.enable_blend,
        .src_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
        .dst_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .color_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE,
        .dst_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .alpha_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
        .color_write_mask = sdl.SDL_GPU_COLORCOMPONENT_R |
            sdl.SDL_GPU_COLORCOMPONENT_G |
            sdl.SDL_GPU_COLORCOMPONENT_B |
            sdl.SDL_GPU_COLORCOMPONENT_A,
        .enable_color_write_mask = false,
    };
    const color_target = sdl.SDL_GPUColorTargetDescription{
        .format = ToSDLTextureFormat(config.color_format),
        .blend_state = blend_state,
    };

    const create_info = sdl.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vert_shader,
        .fragment_shader = frag_shader,

        // No vertex input — fullscreen triangle positions generated in vert shader
        .vertex_input_state = .{
            .vertex_buffer_descriptions = null,
            .num_vertex_buffers = 0,
            .vertex_attributes = null,
            .num_vertex_attributes = 0,
        },

        .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,

        .rasterizer_state = .{
            .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
            .cull_mode = sdl.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
            .enable_depth_bias = false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .enable_depth_clip = false,
        },

        .depth_stencil_state = .{
            .enable_depth_test = false,
            .enable_depth_write = false,
            .compare_op = sdl.SDL_GPU_COMPAREOP_ALWAYS,
            .enable_stencil_test = false,
            .back_stencil_state = std.mem.zeroes(sdl.SDL_GPUStencilOpState),
            .front_stencil_state = std.mem.zeroes(sdl.SDL_GPUStencilOpState),
            .compare_mask = 0,
            .write_mask = 0,
        },

        .multisample_state = .{
            .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
            .sample_mask = 0xFFFFFFFF,
            .enable_mask = false,
        },

        .target_info = .{
            .color_target_descriptions = &color_target,
            .num_color_targets = 1,
            .depth_stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_INVALID,
            .has_depth_stencil_target = false,
        },

        .props = 0,
    };

    const pipeline = sdl.SDL_CreateGPUGraphicsPipeline(device, &create_info);
    if (pipeline == null) {
        std.log.err("SDLGPUPipeline: failed to create pipeline — {s}", .{sdl.SDL_GetError()});
        return error.AssetInitFailed;
    }
    return pipeline.?;
}

fn ToSDLStage(stage: Stage) sdl.SDL_GPUShaderStage {
    return switch (stage) {
        .Vertex => sdl.SDL_GPU_SHADERSTAGE_VERTEX,
        .Fragment => sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
    };
}

fn ToSDLTextureFormat(format: TextureFormat) sdl.SDL_GPUTextureFormat {
    return switch (format) {
        .RGBA8 => sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .BGRA8 => sdl.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
        .RGBA16Float => sdl.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
        .RGBA32Float => sdl.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_FLOAT,
        .Depth32Float => sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
    };
}
