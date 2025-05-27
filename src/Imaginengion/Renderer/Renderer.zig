const std = @import("std");
const builtin = @import("builtin");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const Window = @import("../Windows/Window.zig");

const RenderContext = @import("RenderContext.zig");
const Renderer2D = @import("Renderer2D.zig");
const Renderer3D = @import("Renderer3D.zig");

const AssetManager = @import("../Assets/AssetManager.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const Assets = @import("../Assets/Assets.zig");
const Texture2D = Assets.Texture2D;
const ShaderAsset = Assets.ShaderAsset;

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Mat4f32 = LinAlg.Mat4f32;

const SceneManager = @import("../Scene/SceneManager.zig");
const EntityType = SceneManager.EntityType;
const SceneType = SceneManager.SceneType;
const ECSManagerScenes = SceneManager.ECSManagerScenes;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const ComponentManager = @import("../ECS/ComponentManager.zig");

const EntityComponents = @import("../GameObjects/Components.zig");
const TransformComponent = EntityComponents.TransformComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const SpriteRenderComponent = EntityComponents.SpriteRenderComponent;
const CircleRenderComponent = EntityComponents.CircleRenderComponent;
const CameraComponent = EntityComponents.CameraComponent;

const SceneComponents = @import("../Scene/SceneComponents.zig");
const StackPosComponent = SceneComponents.StackPosComponent;
const SceneComponent = SceneComponents.SceneComponent;

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Renderer = @This();

var RenderM: Renderer = .{};

pub const RenderStats = struct {
    mDrawCalls: usize = 0,
    mTriCount: usize = 0,
    mVertexCount: usize = 0,
    mIndicesCount: usize = 0,

    mSpriteNum: usize = 0,
    mCircleNum: usize = 0,
    mELineNum: usize = 0,
};

const CameraBuffer = extern struct {
    mBuffer: [4][4]f32,
};

const MaxTri: usize = 10_000;
const MaxVerticies: usize = MaxTri * 3;
const MaxIndices: usize = MaxTri * 3;

mRenderContext: RenderContext = undefined,
mStats: RenderStats = .{},

mR2D: Renderer2D = undefined,
mR3D: Renderer3D = undefined,

mTexturesMap: std.AutoHashMap(usize, usize) = undefined,
mTextures: std.ArrayList(AssetHandle) = undefined,

mCameraBuffer: CameraBuffer = std.mem.zeroes(CameraBuffer),
mCameraUniformBuffer: UniformBuffer = undefined,

var RenderAllocator = std.heap.DebugAllocator(.{}).init;

pub fn Init(window: *Window) !void {
    const new_render_context = RenderContext.Init(window);
    RenderM = Renderer{
        .mRenderContext = new_render_context,

        .mR2D = try Renderer2D.Init(
            MaxVerticies,
            MaxIndices,
            RenderAllocator.allocator(),
        ),
        .mR3D = Renderer3D.Init(),

        .mTexturesMap = std.AutoHashMap(usize, usize).init(RenderAllocator.allocator()),
        .mTextures = try std.ArrayList(AssetHandle).initCapacity(RenderAllocator.allocator(), RenderM.mRenderContext.GetMaxTextureImageSlots()),

        .mCameraUniformBuffer = UniformBuffer.Init(@sizeOf(CameraBuffer)),
    };
    try RenderM.mTexturesMap.ensureTotalCapacity(@intCast(RenderM.mRenderContext.GetMaxTextureImageSlots()));
}

pub fn Deinit() !void {
    try RenderM.mR2D.Deinit();
    RenderM.mTexturesMap.deinit();
    RenderM.mTextures.deinit();
}

pub fn SwapBuffers() void {
    RenderM.mRenderContext.SwapBuffers();
}

pub fn OnUpdate(scene_manager: *SceneManager, camera_component: *CameraComponent, camera_transform: *TransformComponent) !void {
    const camera_view_projection = LinAlg.Mat4MulMat4(camera_component.mProjection, LinAlg.Mat4Inverse(camera_transform.GetTransformMatrix()));
    BeginRendering(camera_view_projection);

    try RenderSceneLayers(scene_manager);

    try RenderFinalImage(scene_manager);
}

pub fn RenderSceneLayers(scene_manager: *SceneManager) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ecs_manager = scene_manager.mECSManagerGO;

    const stack_pos_scenes = try scene_manager.mECSManagerSC.GetGroup(.{ .Component = StackPosComponent }, allocator);
    std.sort.insertion(SceneType, stack_pos_scenes.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);

    for (stack_pos_scenes.items) |scene_id| {
        const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };
        BeginScene();

        const scene_component = scene_layer.GetComponent(SceneComponent);
        scene_component.mFrameBuffer.Bind();
        scene_component.mFrameBuffer.ClearFrameBuffer(.{ 0.0, 0.0, 0.0, 1.0 });
        defer scene_component.mFrameBuffer.Unbind();

        var sprite_entities = try ecs_manager.GetGroup(GroupQuery{ .Component = SpriteRenderComponent }, allocator);
        scene_manager.FilterByScene(&sprite_entities, scene_id);

        var circle_entities = try ecs_manager.GetGroup(GroupQuery{ .Component = CircleRenderComponent }, allocator);
        scene_manager.FilterByScene(&circle_entities, scene_id);

        //cull entities that shouldnt be rendered
        CullEntities(SpriteRenderComponent, &sprite_entities, scene_manager);
        CullEntities(CircleRenderComponent, &circle_entities, scene_manager);

        //draw sprites
        //first sort and bind textures
        try TextureSort(SpriteRenderComponent, sprite_entities, scene_manager);
        try DrawSprites(sprite_entities, scene_manager);

        //draw circles
        DrawCircles(circle_entities, scene_manager);

        try EndScene();
    }
}

pub fn BeginRendering(camera_viewprojection: Mat4f32) void {
    RenderM.mCameraBuffer.mBuffer = LinAlg.Mat4ToArray(camera_viewprojection);
    RenderM.mCameraUniformBuffer.SetData(&RenderM.mCameraBuffer, @sizeOf(CameraBuffer), 0);
    RenderM.mStats = std.mem.zeroes(RenderStats);
}

pub fn BeginScene() void {
    RenderM.mR2D.BeginScene();
}

pub fn EndScene() !void {
    RenderM.mCameraUniformBuffer.Bind(0);
    if (RenderM.mR2D.mSpriteVertexCount > 0) {
        try RenderM.mR2D.FlushSprite();
        for (RenderM.mTextures.items, 0..) |asset_handle, i| {
            const texture = try AssetManager.GetAsset(Texture2D, asset_handle.mID);
            texture.Bind(i);
        }
        RenderM.mRenderContext.DrawIndexed(RenderM.mR2D.mSpriteVertexArray, RenderM.mR2D.mSpriteIndexCount);
        RenderM.mStats.mDrawCalls += 1;
    }
    if (RenderM.mR2D.mCircleVertexCount > 0) {
        try RenderM.mR2D.FlushCircle();
        RenderM.mRenderContext.DrawIndexed(RenderM.mR2D.mCircleVertexArray, RenderM.mR2D.mCircleIndexCount);
        RenderM.mStats.mDrawCalls += 1;
    }
    if (RenderM.mR2D.mELineVertexCount > 0) {
        try RenderM.mR2D.FlushELine();
        RenderM.mRenderContext.DrawELines(RenderM.mR2D.mELineVertexArray, RenderM.mR2D.mELineVertexCount);
        RenderM.mStats.mDrawCalls += 1;
    }
}

pub fn RenderFinalImage(scene_manager: *SceneManager) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const scene_stack_entities = try scene_manager.mECSManagerSC.GetGroup(GroupQuery{ .Component = StackPosComponent }, allocator);
    std.sort.insertion(SceneType, scene_stack_entities.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);
    var num_of_scenes = scene_stack_entities.items.len;
    scene_manager.mNumTexturesUniformBuffer.SetData(@ptrCast(&num_of_scenes), @sizeOf(usize), 0);
    scene_manager.mFrameBuffer.Bind();
    defer scene_manager.mFrameBuffer.Unbind();
    scene_manager.mFrameBuffer.ClearFrameBuffer(.{ 0.3, 0.3, 0.3, 1.0 });
    scene_manager.mNumTexturesUniformBuffer.Bind(0);
    const shader_asset = try scene_manager.mCompositeShaderHandle.GetAsset(ShaderAsset);
    shader_asset.mShader.Bind();
    for (scene_stack_entities.items, 0..) |scene_id, i| {
        const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };
        const scene_component = scene_layer.GetComponent(SceneComponent);
        scene_component.mFrameBuffer.BindColorAttachment(0, i);
        scene_component.mFrameBuffer.BindDepthAttachment(i + num_of_scenes);
    }
    RenderM.mRenderContext.DrawIndexed(scene_manager.mCompositeVertexArray, 6);
}

pub fn GetRenderStats() RenderStats {
    return RenderM.mStats;
}

fn CullEntities(comptime component_type: type, result: *std.ArrayList(EntityType), scene_manager: *SceneManager) void {
    std.debug.assert(@hasField(component_type, "mShouldRender"));
    if (result.items.len == 0) return;

    var end_index: usize = result.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const entity_id = result.items[i];
        const render_component = scene_manager.mECSManagerGO.GetComponent(component_type, entity_id);
        if (render_component.mShouldRender == true) {
            i += 1;
        } else {
            result.items[i] = result.items[end_index - 1];
            end_index -= 1;
        }
    }

    result.shrinkAndFree(end_index);
}

fn TextureSort(comptime component_type: type, entity_list: std.ArrayList(EntityType), scene_manager: *SceneManager) !void {
    std.debug.assert(@hasField(component_type, "mTexture"));

    RenderM.mTexturesMap.clearRetainingCapacity();
    RenderM.mTextures.clearRetainingCapacity();

    var i: usize = 0;
    while (i < entity_list.items.len) : (i += 1) {
        const entity_id = entity_list.items[i];
        const render_component = scene_manager.mECSManagerGO.GetComponent(component_type, entity_id);
        if (RenderM.mTexturesMap.contains(render_component.mTexture.mID) == false) {
            try RenderM.mTexturesMap.put(render_component.mTexture.mID, RenderM.mTextures.items.len);
            try RenderM.mTextures.append(render_component.mTexture);
        }
    }
}

fn DrawSprites(sprite_entities: std.ArrayList(EntityType), scene_manager: *SceneManager) !void {
    var i: usize = 0;
    while (i < sprite_entities.items.len) : (i += 1) {
        const entity_id = sprite_entities.items[i];
        const transform_component = scene_manager.mECSManagerGO.GetComponent(TransformComponent, entity_id);
        const sprite_component = scene_manager.mECSManagerGO.GetComponent(SpriteRenderComponent, entity_id);

        RenderM.mR2D.DrawSprite(
            transform_component.GetTransformMatrix(),
            sprite_component.mColor,
            @floatFromInt(RenderM.mTexturesMap.get(sprite_component.mTexture.mID).?),
            sprite_component.mTilingFactor,
            sprite_component.mTexCoords,
        );

        RenderM.mStats.mTriCount += 2;
        RenderM.mStats.mVertexCount += 4;
        RenderM.mStats.mIndicesCount += 6;
        RenderM.mStats.mSpriteNum += 1;
    }
}

fn DrawCircles(circle_entities: std.ArrayList(EntityType), scene_manager: *SceneManager) void {
    var i: usize = 0;
    while (i < circle_entities.items.len) : (i += 1) {
        const entity_id = circle_entities.items[i];
        const transform_component = scene_manager.mECSManagerGO.GetComponent(TransformComponent, entity_id);
        const circle_component = scene_manager.mECSManagerGO.GetComponent(CircleRenderComponent, entity_id);
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
