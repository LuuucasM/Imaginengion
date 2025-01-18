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

    mSpriteNum: u32,
    mCircleNum: u32,
    mELineNum: u32,
};

const MaxTri: u32 = 10_000;
const MaxVerticies: u32 = MaxTri * 3;
const MaxIndices: u32 = MaxTri * 3;

mEngineAllocator: std.mem.Allocator,
mRenderContext: RenderContext,
mR2D: Renderer2D,
mR3D: Renderer3D,

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

    RenderM.mStats = std.mem.zeroes(Stats);

    RenderM.mR2D.StartBatchSprite();
    RenderM.mR2D.StartBatchCircle();
    RenderM.mR2D.StartBatchELine();

    RenderM.mTextureSlotIndex = 1;
}

pub fn EndScene() void {
    if (RenderM.mR2D.mSpriteVertexCount > 0) {
        RenderM.mR2D.FlushSprite();
        RenderM.mRenderContext.DrawIndexed(RenderM.mR2D.mSpriteVertexArray, RenderM.mR2D.mSpriteIndexCount);
        RenderM.mStats.mDrawCalls += 1;
    }
    if (RenderM.mR2D.mCircleVertexCount > 0) {
        RenderM.mR2D.FlushCircle();
        RenderM.mRenderContext.DrawIndexed(RenderM.mR2D.mCircleVertexArray, RenderM.mR2D.mCircleIndexCount);
        RenderM.mStats.mDrawCalls += 1;
    }
    if (RenderM.mR2D.mELineVertexCount > 0) {
        RenderM.mR2D.FlushELine();
        RenderM.mRenderContext.DrawIndexed(RenderM.mR2D.mELineVertexArray, RenderM.mR2D.mELineIndexCount);
        RenderM.mStats.mDrawCalls += 1;
    }
}

pub fn DrawSprite(transform: Mat4f32, color: Vec4f32, texture_index: f32, tiling_factor: f32) void {
    RenderM.mR2D.DrawSprite(transform, color, texture_index, tiling_factor);

    RenderM.mStats.mTriCount += 2;
    RenderM.mStats.mVertexCount += 4;
    RenderM.mStats.mIndicesCount += 6;
    RenderM.mStats.mSpriteNum += 1;
}
pub fn DrawCircle(transform: Mat4f32, color: Vec4f32, thickness: f32, fade: f32) void {
    RenderM.mR2D.DrawCircle(transform, color, thickness, fade);

    RenderM.mStats.mTriCount += 2;
    RenderM.mStats.mVertexCount += 4;
    RenderM.mStats.mIndicesCount += 6;
    RenderM.mStats.mCircleNum += 1;
}

pub fn DrawELine(p0: Vec3f32, p1: Vec3f32, color: Vec4f32, thickness: f32) void {
    RenderM.mR2D.DrawELine(p0, p1, color, thickness);

    RenderM.mStats.mVertexCount += 2;
    RenderM.mStats.mELineNum += 1;
}

pub fn Draw3D() void {}
