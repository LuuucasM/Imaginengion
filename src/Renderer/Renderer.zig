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
mTexturesMap: std.AutoHashMap(u32, usize),
mTextures: std.ArrayList(AssetHandle),

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

        .mTexturesMap = std.AutoHashMap(u32, usize).init(EngineAllocator),
        .mTextures = try std.ArrayList(AssetHandle).initCapacity(EngineAllocator, RenderM.mRenderContext.GetMaxTextureImageSlots()),
    };
    try RenderM.mTexturesMap.ensureTotalCapacity(@intCast(RenderM.mRenderContext.GetMaxTextureImageSlots()));
}

pub fn Deinit() void {
    RenderM.mTexturesMap.deinit();
    RenderM.mTextures.deinit();
    RenderM.mEngineAllocator.destroy(RenderM);
}

pub fn SwapBuffers() void {
    RenderM.mRenderContext.SwapBuffers();
}

pub fn RenderSceneLayer(ecs_manager: ECSManager, camera_projection: Mat4f32, camera_transform: Mat4f32) !void {
    RenderM.mR2D.mCameraBuffer = LinAlg.Mat4MulMat4(camera_projection, LinAlg.Mat4Inverse(camera_transform));
    RenderM.mR2D.mCameraUniformBuffer.SetData(&RenderM.mR2D.mCameraBuffer, @sizeOf(Mat4f32), 0);

    BeginScene();
    defer EndScene();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sprite_entities = try ecs_manager.GetGroup(&[_]type{ TransformComponent, SpriteRenderComponent }, allocator);
    const circle_entities = try ecs_manager.GetGroup(&[_]type{ TransformComponent, CircleRenderComponent }, allocator);

    //cull entities that shouldnt be rendered
    const sprite_end_index = CullEntities(SpriteRenderComponent, sprite_entities, ecs_manager);
    const circle_end_index = CullEntities(CircleRenderComponent, circle_entities, ecs_manager);

    //ensure textures are ready to go for draw
    try TextureSort(SpriteRenderComponent, sprite_entities, sprite_end_index, ecs_manager);
    DrawSprites(sprite_entities, sprite_end_index, ecs_manager);
    DrawCircles(circle_entities, circle_end_index, ecs_manager);
}

pub fn BeginScene() void {
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

fn CullEntities(comptime component_type: type, entity_list: std.ArrayList(u32), ecs_manager: ECSManager) usize {
    std.debug.assert(@hasField(component_type, "mShouldRender"));

    var write_index: usize = 0;
    var read_index: usize = 0;

    while (read_index < entity_list.items.len) : (read_index += 1) {
        const entity_id = entity_list.items[read_index];
        const render_component = ecs_manager.GetComponent(component_type, entity_id);

        if (render_component.mShouldRender == true) {
            const temp = entity_list.items[write_index];
            entity_list.items[write_index] = entity_list.items[read_index];
            entity_list.items[read_index] = temp;
            write_index += 1;
        }
    }
    return write_index;
}

fn TextureSort(comptime component_type: type, entity_list: std.ArrayList(u32), entity_list_end_index: usize, ecs_manager: ECSManager) !void {
    std.debug.assert(@hasField(component_type, "mTexture"));

    RenderM.mTexturesMap.clearRetainingCapacity();
    RenderM.mTextures.clearRetainingCapacity();

    var i: usize = 0;
    while (i < entity_list_end_index) : (i += 1) {
        const entity_id = entity_list.items[i];
        const render_component = ecs_manager.GetComponent(component_type, entity_id);
        if (RenderM.mTexturesMap.contains(render_component.mTexture.mID) == false) {
            try RenderM.mTexturesMap.put(render_component.mTexture.mID, RenderM.mTextures.items.len);
            try RenderM.mTextures.append(render_component.mTexture);
        }
    }
}

fn DrawSprites(sprite_entities: std.ArrayList(u32), sprite_end_index: usize, ecs_manager: ECSManager) void {
    var i: usize = 0;
    while (i < sprite_end_index) : (i += 1) {
        const entity_id = sprite_entities.items[i];
        const transform_component = ecs_manager.GetComponent(TransformComponent, entity_id);
        const sprite_component = ecs_manager.GetComponent(SpriteRenderComponent, entity_id);

        std.debug.assert(RenderM.mTexturesMap.contains(sprite_component.mTexture.mID));

        RenderM.mR2D.DrawSprite(
            transform_component.GetTransformMatrix(),
            sprite_component.mColor,
            @floatFromInt(RenderM.mTextures.items[RenderM.mTexturesMap.get(sprite_component.mTexture.mID).?].mID),
            sprite_component.mTilingFactor,
        );

        RenderM.mStats.mTriCount += 2;
        RenderM.mStats.mVertexCount += 4;
        RenderM.mStats.mIndicesCount += 6;
        RenderM.mStats.mSpriteNum += 1;
    }
}

fn DrawCircles(circle_entities: std.ArrayList(u32), circle_end_index: usize, ecs_manager: ECSManager) void {
    var i: usize = 0;
    while (i < circle_end_index) : (i += 1) {
        const entity_id = circle_entities.items[i];
        const transform_component = ecs_manager.GetComponent(TransformComponent, entity_id);
        const circle_component = ecs_manager.GetComponent(CircleRenderComponent, entity_id);
        RenderM.mR2D.DrawCircle(transform_component.GetTransformMatrix(), circle_component.mColor, circle_component.mThickness, circle_component.mFade);

        RenderM.mStats.mTriCount += 2;
        RenderM.mStats.mVertexCount += 4;
        RenderM.mStats.mIndicesCount += 6;
        RenderM.mStats.mSpriteNum += 1;
    }
}

fn DrawELine(p0: Vec3f32, p1: Vec3f32, color: Vec4f32, thickness: f32) void {
    RenderM.mR2D.DrawELine(p0, p1, color, thickness);

    RenderM.mStats.mVertexCount += 2;
    RenderM.mStats.mELineNum += 1;
}
