const std = @import("std");
const builtin = @import("builtin");
const RenderContext = @import("RenderContext.zig");
const Renderer2D = @import("Renderer2D.zig");
const Renderer3D = @import("Renderer3D.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Mat4f32 = LinAlg.Mat4f32;

const Renderer = @This();

var RenderM: *Renderer = undefined;

const Stats = struct {
    mDrawCalls: u32,
    mTriCount: u32,
    mVertexCount: u32,
    mIndicesCount: u32,
};

const MaxTri: u32 = 20_000;
const MaxVerticies: u32 = MaxTri * 3;
const MaxIndices: u32 = MaxTri * 3;

mEngineAllocator: std.mem.Allocator,
mRenderContext: RenderContext,
mR2D: Renderer2D,
mR3D: Renderer3D,
mTextureSlots: std.ArrayList(AssetHandle),
mTextureSlotIndex: u32,
mSpriteTextureToIndex: std.AutoHashMap(u32, usize),
mStats: Stats,

var RenderAllocator = std.heap.GeneralPurposeAllocator(.{}){};

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    const new_render_context = RenderContext.Init();
    RenderM = try EngineAllocator.create(Renderer);
    RenderM.* = .{
        .mEngineAllocator = EngineAllocator,
        .mRenderContext = new_render_context,
        .mR2D = Renderer2D.Init(
            MaxVerticies,
            MaxIndices,
            RenderAllocator.allocator(),
        ),
        .mR3D = Renderer3D.Init(),
        .mTextureSlots = std.ArrayList(AssetHandle).initCapacity(RenderAllocator.allocator(), new_render_context.GetMaxTextureImageSlots()),
        .mTextureSlotIndex = 1,
        .mSpriteTextureIndexs = std.AutoHashMap(u32, usize).init(RenderAllocator.allocator()),
        .mStats = .{ .mDrawCalls = 0, .mTriCount = 0 },
    };
}

pub fn Deinit() void {
    RenderM.mEngineAllocator.destroy(RenderM);
}

pub fn SwapBuffers() void {
    RenderM.mRenderContext.SwapBuffers();
}

pub fn BeginScene(camera_projection: Mat4f32, camera_transform: Mat4f32) void {
    RenderM.mR2D.mCameraBuffer = LinAlg.Mat4Mul(camera_projection, LinAlg.Mat4Inverse(camera_transform));
    RenderM.mR2D.mCameraUniformBuffer.SetData(&RenderM.mR2D.mCameraBuffer, @sizeOf(Mat4f32), 0);

    ResetStats();
    StartBatch();
}

pub fn EndScene() void {
    FlushScene();
}

pub fn DrawSprite(transform: Mat4f32, texture: AssetHandle, tiling_factor: f32, color: Vec4f32) void {
    if (RenderM.mR2D.mSpriteIndexCount + 6 > MaxIndices or RenderM.mTextureSlotIndex + 1 > RenderM.mTextureSlots.capacity) {
        RenderM.mR2D.FlushSprite();
        RenderM.mR2D.StartBatchSprite();
    }

    var texture_index: f32 = 0.0;
    if (RenderM.mSpriteTextureToIndex.get(texture.mID)) |index| {
        texture_index = @floatFromInt(index);
    } else {
        //TODO: texture_index =
    }

    if (texture_index == 0.0) {
        texture_index = @floatFromInt(RenderM.mTextureSlotIndex);
        RenderM.mTextureSlots.append(texture);
        RenderM.mTextureSlotIndex += 1;

        //TODO: texture_index =
    }

    RenderM.mR2D.DrawSprite(transform, texture_index, tiling_factor, color);

    RenderM.mStats.mTriCount += 2;
    RenderM.mStats.mVertexCount += 4;
    RenderM.mStats.mIndicesCount += 6;
}
pub fn DrawCircle(transform: Mat4f32, color: Vec4f32, thickness: f32, fade: f32) void {
    ShouldResetBatch(2, 4, 6);

    RenderM.mR2D.DrawCircle(transform, color, thickness, fade);

    RenderM.mStats.mTriCount += 2;
    RenderM.mStats.mVertexCount += 4;
    RenderM.mStats.mIndicesCount += 6;
}

pub fn Draw3D() void {}

fn StartBatch() void {
    RenderM.mR2D.StartBatch();

    RenderM.mTextureSlotIndex = 1;
}

fn FlushScene() void {
    if (RenderM.mR2D.mSpriteIndexCount > 0) {
        const data_size: u32 = @intFromPtr(RenderM.mR2D.mSpriteVertexBufferPtr) - @intFromPtr(RenderM.mR2D.mSpriteVertexBufferBase);
        RenderM.mR2D.mSpriteVertexBuffer.SetData(RenderM.mR2D.mSpriteVertexBufferBase, data_size);

        var i: usize = 0;
        while (i < RenderM.mTextureSlotIndex) : (i += 1) {
            RenderM.mTextureSlots.items[i].Bind();
        }

        RenderM.mR2D.mSpriteShader.Bind();
        RenderM.mRenderContext.DrawIndexed(RenderM.mR2D.mSpriteVertexArray, RenderM.mR2D.mSpriteIndexCount);
        RenderM.mStats.mDrawCalls += 1;
    }
    if (RenderM.mR2D.mCircleIndexCount > 0) {
        const data_size: u32 = @intFromPtr(RenderM.mR2D.mCircleVertexBufferPtr) - @intFromPtr(RenderM.mR2D.mCircleVertexBufferBase);
        RenderM.mR2D.mCircleVertexBuffer.SetData(RenderM.mR2D.mCircleVertexBufferBase, data_size);

        RenderM.mR2D.mCircleShader.Bind();
        RenderM.mRenderContext.DrawIndexed(RenderM.mR2D.mCircleVertexArray, RenderM.mR2D.mCircleIndexCount);
        RenderM.mStats.mDrawCalls += 1;
    }
    if (RenderM.mR2D.mELineIndexCount > 0) {
        const data_size: u32 = @intFromPtr(RenderM.mR2D.mELineVertexBufferPtr) - @intFromPtr(RenderM.mR2D.ELineVertexBufferBase);
        RenderM.mR2D.mELineVertexBuffer.SetData(RenderM.mR2D.mELineVertexBufferBase, data_size);

        RenderM.mR2D.mELineShader.Bind();
        RenderM.mRenderContext.DrawIndexed(RenderM.mR2D.mELineVertexArray, RenderM.mR2D.mELineIndexCount);
        RenderM.mStats.mDrawCalls += 1;
    }
}

fn ShouldResetBatch(new_tri_count: u32, new_vertex_count: u32, new_indices_count: u32, new_textures_count: u32) void {
    if (RenderM.mTriCount + new_tri_count > MaxTri or RenderM.mVertexCount + new_vertex_count > MaxVerticies or RenderM.mIndicesCount + new_indices_count > MaxIndices or RenderM.mTextureSlotIndex + new_textures_count > RenderM.mTextureSlots.capacity) {
        FlushScene();
        StartBatch();
    }
}

fn ResetStats() void {
    RenderM.mStats = std.mem.zeroes(Stats);
}
