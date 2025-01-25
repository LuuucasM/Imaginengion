const std = @import("std");
const builtin = @import("builtin");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;

const RenderContext = @import("RenderContext.zig");
const Renderer2D = @import("Renderer2D.zig");
const Renderer3D = @import("Renderer3D.zig");

const AssetHandle = @import("../Assets/AssetHandle.zig");

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Mat4f32 = LinAlg.Mat4f32;

const ECSManager = @import("../ECS/ECSManager.zig");

const Components = @import("../GameObjects/Components.zig");
const TransformComponent = Components.TransformComponent;
const SpriteRenderComponent = Components.SpriteRenderComponent;
const CircleRenderComponent = Components.CircleRenderComponent;

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
        .mR2D = try Renderer2D.Init(
            MaxVerticies,
            MaxIndices,
            RenderAllocator.allocator(),
        ),
        .mR3D = Renderer3D.Init(),
        .mStats = std.mem.zeroes(Stats),
    };
}

pub fn Deinit() void {
    RenderM.mEngineAllocator.destroy(RenderM);
}

pub fn SwapBuffers() void {
    RenderM.mRenderContext.SwapBuffers();
}

pub fn RenderSceneLayer(ecs_manager: ECSManager, camera_projection: Mat4f32, camera_transform: Mat4f32) !void {
    BeginScene(camera_projection, camera_transform);
    defer EndScene();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sprite_entities = try ecs_manager.GetGroup(&[_]type{SpriteRenderComponent}, allocator);
    DrawSprites(sprite_entities, ecs_manager);
    const circle_entities = try ecs_manager.GetGroup(&[_]type{CircleRenderComponent}, allocator);
    DrawCircles(circle_entities, ecs_manager);
}

pub fn BeginScene(camera_projection: Mat4f32, camera_transform: Mat4f32) void {
    RenderM.mR2D.mCameraBuffer = LinAlg.Mat4MulMat4(camera_projection, LinAlg.Mat4Inverse(camera_transform));
    RenderM.mR2D.mCameraUniformBuffer.SetData(&RenderM.mR2D.mCameraBuffer, @sizeOf(Mat4f32), 0);

    RenderM.mStats = std.mem.zeroes(Stats);

    RenderM.mR2D.StartBatchSprite();
    RenderM.mR2D.StartBatchCircle();
    RenderM.mR2D.StartBatchELine();
}

pub fn EndScene() void {
    if (RenderM.mR2D.mSpriteVertexCount > 0) {
        RenderM.mR2D.FlushSprite();
        RenderM.mRenderContext.DrawIndexed(RenderM.mR2D.mSpriteVertexArray, RenderM.mR2D.mSpriteVertexCount);
        RenderM.mStats.mDrawCalls += 1;
    }
    if (RenderM.mR2D.mCircleVertexCount > 0) {
        RenderM.mR2D.FlushCircle();
        RenderM.mRenderContext.DrawIndexed(RenderM.mR2D.mCircleVertexArray, RenderM.mR2D.mCircleVertexCount);
        RenderM.mStats.mDrawCalls += 1;
    }
    if (RenderM.mR2D.mELineVertexCount > 0) {
        RenderM.mR2D.FlushELine();
        RenderM.mRenderContext.DrawIndexed(RenderM.mR2D.mELineVertexArray, RenderM.mR2D.mELineVertexCount);
        RenderM.mStats.mDrawCalls += 1;
    }
}

fn DrawSprites(sprite_entities: ArraySet(u32), ecs_manager: ECSManager) void {
    var iter = sprite_entities.iterator();
    while (iter.next()) |entry| {
        const entity_id = entry.key_ptr.*;
        const transform_component = ecs_manager.GetComponent(TransformComponent, entity_id);
        const sprite_component = ecs_manager.GetComponent(SpriteRenderComponent, entity_id);
        RenderM.mR2D.DrawSprite(transform_component.GetTransformMatrix(), sprite_component.mColor, 0, sprite_component.mTilingFactor); // TODO change 0 to actual texture index

        RenderM.mStats.mTriCount += 2;
        RenderM.mStats.mVertexCount += 4;
        RenderM.mStats.mIndicesCount += 6;
        RenderM.mStats.mSpriteNum += 1;
    }
}

fn DrawCircles(circle_entities: ArraySet(u32), ecs_manager: ECSManager) void {
    var iter = circle_entities.iterator();
    while (iter.next()) |entry| {
        const entity_id = entry.key_ptr.*;
        const transform_component = ecs_manager.GetComponent(TransformComponent, entity_id);
        const circle_component = ecs_manager.GetComponent(CircleRenderComponent, entity_id);
        RenderM.mR2D.DrawCircle(transform_component.GetTransformMatrix(), circle_component.mColor, circle_component.mThickness, circle_component.mFade); // TODO change 0 to actual texture index

        RenderM.mStats.mTriCount += 2;
        RenderM.mStats.mVertexCount += 4;
        RenderM.mStats.mIndicesCount += 6;
        RenderM.mStats.mCircleNum += 1;
    }
}

fn DrawELine(p0: Vec3f32, p1: Vec3f32, color: Vec4f32, thickness: f32) void {
    RenderM.mR2D.DrawELine(p0, p1, color, thickness);

    RenderM.mStats.mVertexCount += 2;
    RenderM.mStats.mELineNum += 1;
}
