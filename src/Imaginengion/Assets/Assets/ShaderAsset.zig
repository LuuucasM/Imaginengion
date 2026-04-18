const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const builtin = @import("builtin");
const VertexBufferElement = @import("../../VertexBuffers/VertexBufferElement.zig");
const Tracy = @import("../../Core/Tracy.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const ShaderAsset = @This();

const ShaderManifest = struct {
    mVertexPath: []const u8,
    mFragmentPath: []const u8,
    mVertexUniformBuffers: u32 = 0,
    mVertexStorageBuffers: u32 = 0,
    mVertexSamplers: u32 = 0,
    mFragmentUniformBuffers: u32 = 0,
    mFragmentStorageBuffers: u32 = 0,
    mFragmentSamplers: u32 = 0,
};

const ShaderSources = struct {
    mVertexBinary: []const u8,
    mFragmentBinary: []const u8,
    mManifest: ShaderManifest,
};

pub const Name: []const u8 = "ShaderAsset";
pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == ShaderAsset) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mShaderSources: ShaderSources = undefined,

pub fn Init(self: *ShaderAsset, engine_context: *EngineContext, abs_path: []const u8, _: []const u8, asset_file: std.fs.File) !void {
    const zone = Tracy.ZoneInit("Shader Init", @src());
    defer zone.Deinit();

    const file_path = std.fs.path.dirname(abs_path).?;

    const file_size = try asset_file.getEndPos();
    const json_buf = try engine_context.FrameAllocator().alloc(u8, file_size);
    _ = try asset_file.readAll(json_buf);

    const manifest = try std.json.parseFromSliceLeaky(
        ShaderManifest,
        engine_context.FrameAllocator(),
        json_buf,
        .{ .allocate = .alloc_if_needed },
    );

    const vert_binary = try LoadSpirvFile(engine_context, file_path, manifest.mVertex);
    const frag_binary = try LoadSpirvFile(engine_context, file_path, manifest.mFragment);

    std.debug.assert(vert_binary.len % 4 == 0);
    std.debug.assert(frag_binary.len % 4 == 0);

    self.mShaderSources = .{
        .mVertexCode = vert_binary,
        .mFragmentCode = frag_binary,
        .mManifest = manifest,
    };
}

pub fn Deinit(self: *ShaderAsset, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Shader Deinit", @src());
    defer zone.Deinit();

    const engine_allocator = engine_context.EngineAllocator();

    engine_allocator.free(self.mShaderSources.mVertexBinary);
    engine_allocator.free(self.mShaderSources.mFragmentBinary);
}

fn LoadSpirvFile(engine_context: *EngineContext, dir: []const u8, name: []const u8) ![]const u8 {
    const path = try std.fs.path.join(engine_context.FrameAllocator(), &.{ dir, name });
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const size = try file.getEndPos();
    const buf = try engine_context.EngineAllocator().alloc(u8, size);
    _ = try file.readAll(buf);
    return buf;
}
