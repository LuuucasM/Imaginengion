const std = @import("std");
const builtin = @import("builtin");
const RenderContext = @import("RenderContext.zig");
const Renderer2D = @import("Renderer2D.zig");
const Renderer3D = @import("Renderer3D.zig");
const EditorCamera = @import("../Camera/EditorCamera.zig");

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Mat4f32 = LinAlg.Mat4f32;

const Renderer = @This();

var RenderM: *Renderer = undefined;

const MaxTri: u32 = 20_000;
const MaxVerticies: u32 = MaxTri * 3;
const MaxIndices: u32 = MaxTri * 3;

mEngineAllocator: std.mem.Allocator,
mRenderContext: RenderContext,
mR2D: Renderer2D,
mR3D: Renderer3D,

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    const new_render_context = RenderContext.Init();
    RenderM = try EngineAllocator.create(Renderer);
    RenderM.* = .{
        .mEngineAllocator = EngineAllocator,
        .mRenderContext = new_render_context,
        .mR2D = Renderer2D.Init(
            MaxTri,
            MaxVerticies,
            MaxIndices,
            new_render_context.GetMaxTextureImageSlots(),
        ),
        .mR3D = Renderer3D.Init(),
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

    StartBatch();
}

pub fn EndScene() void {
    FlushScene();
}

pub fn Draw2D() void {}

pub fn Draw3D() void {}

fn StartBatch() void {
    RenderM.mR2D.mSpriteIndexCount = 0;
    RenderM.mR2D.mSpriteVertexBufferPtr = RenderM.mR2D.mSpriteVertexBufferBase;

    RenderM.mR2D.mCircleIndexCount = 0;
    RenderM.mR2D.mCircleVertexBufferPtr = RenderM.mR2D.mCircleVertexBufferBase;

    RenderM.mR2D.mELineIndexCount = 0;
    RenderM.mR2D.mELineVertexBufferPtr = RenderM.mR2D.mELineVertexBufferBase;

    RenderM.mR2D.mTextureSlotIndex = 1;
}

fn NextBatch() void {
    FlushScene();
    StartBatch();
}

fn FlushScene() void {
    if (RenderM.mR2D.mSpriteIndexCount > 0) {
        const data_size: u32 = @intFromPtr(RenderM.mR2D.mSpriteVertexBufferPtr) - @intFromPtr(RenderM.mR2D.mSpriteVertexBufferBase);
        RenderM.mR2D.mSpriteVertexBuffer.SetData(RenderM.mR2D.mSpriteVertexBufferBase, data_size);
    }
    if (RenderM.mR2D.mCircleIndexCount > 0) {}
    if (RenderM.mR2D.mELineIndexCount > 0) {}
}
