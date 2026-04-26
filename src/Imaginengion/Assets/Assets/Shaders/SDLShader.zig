const std = @import("std");
const sdl = @import("../../../Core/CImports.zig").sdl;
const EngineContext = @import("../../../Core/EngineContext.zig");
const ShaderManifest = @import("../ShaderAsset.zig").ShaderManifest;
const ShaderSources = @import("../ShaderAsset.zig").ShaderSources;
const StageInfo = @import("../ShaderAsset.zig").StageInfo;

const PARSE_OPTIONS = std.json.ParseOptions{ .allocate = .alloc_if_needed, .max_value_len = std.json.default_max_value_len };

const build_options = @import("build_options");
pub const enable_nsight = build_options.enable_nsight;

const SDLShader = @This();

mPipeline: ?*sdl.SDL_GPUGraphicsPipeline,

pub fn Init(self: *SDLShader, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, asset_file: std.fs.File, config: PipelineConfig) !void {
    const frame_allocator = engine_context.FrameAllocator();

    const sources: ShaderSources = try ReadFile(asset_file, frame_allocator, abs_path);

    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mRenderContext.GetDevice()));

    const vert_shader = CreateShaderStage(device, sources.mVertexCode, .{
        .mStage = sdl.SDL_GPU_SHADERSTAGE_VERTEX,
        .mNumUniformBuffers = sources.mManifest.mVertexUniformBuffers,
        .mNumStorageBuffers = sources.mManifest.mVertexStorageBuffers,
        .mNumSamplers = sources.mManifest.mVertexSamplers,
    }, rel_path) orelse return error.AssetInitFailed;

    const frag_shader = CreateShaderStage(device, sources.mFragmentCode, .{
        .mStage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
        .mNumUniformBuffers = sources.mManifest.mFragmentUniformBuffers,
        .mNumStorageBuffers = sources.mManifest.mFragmentStorageBuffers,
        .mNumSamplers = sources.mManifest.mFragmentSamplers,
    }, rel_path) orelse return error.AssetInitFailed;

    self.mPipeline = try CreatePipeline(device, vert_shader, frag_shader, config);

    sdl.SDL_ReleaseGPUShader(device, vert_shader);
    sdl.SDL_ReleaseGPUShader(device, frag_shader);
}

pub fn Deinit(self: *SDLShader, engine_context: *EngineContext) void {
    std.debug.assert(self.mPipeline != null);
    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mRenderContext.GetDevice()));
    sdl.SDL_ReleaseGPUGraphicsPipeline(device, self.mPipeline);
    self.mPipeline = null;
}

pub fn Bind(self: SDLShader, engine_context: *EngineContext) void {
    const render_pass: *sdl.SDL_GPURenderPass = @ptrCast(@alignCast(engine_context.mRenderer.mRenderContext.GetRenderPass()));
    sdl.SDL_BindGPUGraphicsPipeline(render_pass, self.mPipeline);
}

fn CreateShaderStage(device: *sdl.SDL_GPUDevice, code: []const u8, info: StageInfo, rel_path: []const u8) ?*sdl.SDL_GPUShader {
    const create_info = sdl.SDL_GPUShaderCreateInfo{
        .code_size = code.len,
        .code = code.ptr,
        .entrypoint = "main",
        .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = info.mStage,
        .num_samplers = info.mNumSamplers,
        .num_storage_textures = 0,
        .num_storage_buffers = info.mNumStorageBuffers,
        .num_uniform_buffers = info.mNumUniformBuffers,
    };

    const shader = sdl.SDL_CreateGPUShader(device, &create_info);
    if (shader == null) {
        std.log.err("Failed to create {s} shader stage for: {s} - {s}", .{
            if (info.mStage == sdl.SDL_GPU_SHADERSTAGE_VERTEX) "vertex" else "fragment",
            rel_path,
            sdl.SDL_GetError(),
        });
    }
    return shader;
}

fn CreatePipeline(device: *sdl.SDL_GPUDevice, vert_shader: *sdl.SDL_GPUShader, frag_shader: *sdl.SDL_GPUShader, config: PipelineConfig) !*sdl.SDL_GPUGraphicsPipeline {
    const blend_state = sdl.SDL_GPUColorTargetBlendState{
        .enable_blend = config.mEnableBlend,
        .src_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
        .dst_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .color_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE,
        .dst_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .alpha_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
        .color_write_mask = sdl.SDL_GPU_COLORCOMPONENT_R | sdl.SDL_GPU_COLORCOMPONENT_g | sdl.SDL_GPU_COLORCOMPONENT_B | sdl.SDL_GPU_COLORCOMPONENT_A,
        .enable_color_write_mask = false,
    };
    const color_target = sdl.SDL_GPUColorTargetDescription{
        .format = ToSDLTextureFormat(config.mColorTargetFormat),
        .blend_state = blend_state,
    };
    const create_info = sdl.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vert_shader,
        .fragment_shader = frag_shader,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = null,
            .num_vertex_buffers = 0,
            .vertex_attributes = null,
            .num_vertex_attributes = 0,
        },
        .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .fill_mode = ToSDLFillMode(config.mFillMode),
            .cull_mode = ToSDLCullMode(config.mCullMode),
            .front_face = sdl.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
            .enable_depth_bias = false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .enable_depth_clip = false,
        },
        .depth_stencil_state = .{
            .enable_depth_test = config.mEnableDepthTest,
            .enable_depth_write = config.mDepthWriteEnable,
            .compare_op = sdl.SDL_GPU_COMPAREOP_LESS,
            .enable_stencil_test = false,
            .back_stencil_state = std.mem.zeroes(sdl.SDL_GPUStencilOpState),
            .front_stencil_state = std.mem.zeroes(std.mem.zeroes(sdl.SDL_GPUStencilOpState)),
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
        .props = 9,
    };

    const pipeline = sdl.SDL_CreateGPUGraphicsPipeline(device, &create_info);
    if (pipeline == null) {
        std.log.err("Failed to create graphics pipline - {s}", .{sdl.SDL_GetError()});
        return error.AssetInitFailed;
    }
    return pipeline;
}

fn ReadFile(asset_file: std.fs.File, frame_allcoator: std.mem.Allocator, abs_path: []const u8) !ShaderSources {
    const file_path = std.fs.path.dirname(abs_path).?;

    const file_size = try asset_file.getEndPos();
    const json_buf = try frame_allcoator.alloc(u8, file_size);
    _ = try asset_file.readAll(json_buf);

    const manifest = try std.json.parseFromSliceLeaky(
        ShaderManifest,
        frame_allcoator,
        json_buf,
        .{ .allocate = .alloc_if_needed },
    );

    const vert_code = try LoadSpirvFile(frame_allcoator, file_path, manifest.mVertex);
    const frag_code = try LoadSpirvFile(frame_allcoator, file_path, manifest.mFragment);

    return ShaderSources{
        .mVertexCode = vert_code,
        .mFragmentCode = frag_code,
        .mManifest = manifest,
    };
}

fn LoadSpirvFile(frame_allocator: std.mem.Allocator, dir: []const u8, name: []const u8) ![]const u8 {
    const path = try std.fs.path.join(frame_allocator, &.{ dir, name });
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const size = try file.getEndPos();
    const buf = try frame_allocator.alloc(u8, size);
    _ = try file.readAll(buf);
    return buf;
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

fn ToSDLCullMode(format: CullMode) sdl.SDL_GPUCullMode {
    return switch (format) {
        .None => return sdl.SDL_GPU_CULLMODE_NONE,
        .Front => return sdl.SDL_GPU_CULLMODE_FRONT,
        .Back => return sdl.SDL_GPU_CULLMODE_BACK,
    };
}

fn ToSDLFillMode(format: FillMode) sdl.SDL_GPUFillMode {
    return switch (format) {
        .Fill => return sdl.SDL_GPU_FILLMODE_FILL,
        .Line => return sdl.SDL_GPU_FILLMODE_LINE,
    };
}
