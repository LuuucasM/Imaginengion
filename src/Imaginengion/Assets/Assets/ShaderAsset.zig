const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const builtin = @import("builtin");
const VertexBufferElement = @import("../../VertexBuffers/VertexBufferElement.zig");
const Tracy = @import("../../Core/Tracy.zig");
const EngineContext = @import("../../Core/EngineContext.zig");

const Impl = switch (builtin.os.tag) {
    .windows => @import("Shaders/SDLShader.zig"),
    else => @import("Shaders/UnsupportedShader.zig"),
};

pub const TextureFormat = enum {
    None,
    RGBA8,
    BGRA8,
    RGBA16Float,
    RGBA32Float,
    Depth32Float,
};

pub const CullMode = enum {
    None,
    Front,
    Back,
};
pub const FillMode = enum {
    Fill,
    Line,
};

pub const PipelineConfig = struct {
    mColorTargetFormat: TextureFormat,
    mEnableDepthTest: bool = false,
    mDepthWriteEnable: bool = false,
    mEnableBlend: bool = true,
    mCullMode: CullMode = .None,
    mFillMode: FillMode = .Fill,
};

const ShaderAsset = @This();

pub const Name: []const u8 = "ShaderAsset";
pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == ShaderAsset) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mImpl: Impl = .{},

pub fn Init(self: *ShaderAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, asset_file: std.fs.File, config: PipelineConfig) !void {
    const zone = Tracy.ZoneInit("Shader Init", @src());
    defer zone.Deinit();
    try self.mImpl.Init(engine_context, abs_path, rel_path, asset_file, config);
}

pub fn Deinit(self: *ShaderAsset, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Shader Deinit", @src());
    defer zone.Deinit();
    try self.mImpl.Deinit(engine_context);
}

pub fn Bind(self: ShaderAsset, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("Shader Bind", @src());
    defer zone.Deinit();
    self.mImpl.Bind(engine_context);
}
