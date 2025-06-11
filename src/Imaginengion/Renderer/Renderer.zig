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
const SceneType = SceneManager.SceneType;
const ECSManagerScenes = SceneManager.ECSManagerScenes;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const ComponentManager = @import("../ECS/ComponentManager.zig");

const Entity = @import("../GameObjects/Entity.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const TransformComponent = EntityComponents.TransformComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const QuadComponent = EntityComponents.QuadComponent;
const SpriteRenderComponent = EntityComponents.SpriteRenderComponent;
const CircleRenderComponent = EntityComponents.CircleRenderComponent;
const CameraComponent = EntityComponents.CameraComponent;
const EntityChildComponent = EntityComponents.ChildComponent;

const SceneComponents = @import("../Scene/SceneComponents.zig");
const StackPosComponent = SceneComponents.StackPosComponent;
const SceneComponent = SceneComponents.SceneComponent;

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Renderer = @This();

var RenderM: Renderer = .{};

pub const RenderStats = struct {
    mQuadNum: usize = 0,
    mCircleNum: usize = 0,
    mLineNum: usize = 0,
};

const CameraBuffer = extern struct {
    mBuffer: [4][4]f32,
};

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

        .mR2D = try Renderer2D.Init(RenderAllocator.allocator()),
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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const camera_view_projection = LinAlg.Mat4MulMat4(camera_component.mProjection, LinAlg.Mat4Inverse(camera_transform.GetTransformMatrix()));
    BeginRendering(camera_view_projection);
    //I can probably put the new SDF shader inside the renderer since its going to take ALL the shapes from the entire scene so i dont need individual like quad shader
    //circle shader, sphere shader, etc.

    //get all the shapes
    const shapes_ids = try scene_manager.GetEntityGroup(GroupQuery{ .Component = QuadComponent }, allocator);
    //TODO: cull

    //TODO: FINISH DOING THIS
    //TODO: I just changed the way transforms are calculated to take into account the new
    //entity hierarchy so change rendering to fit this system
    //aka all the world transform matrixes should already be calculated so dont need to worry about parents or stuff
    //just pass the entities transform in raw
    for (shapes_ids.items) |shape_entity_id| {
        const entity = scene_manager.GetEntity(shape_entity_id);
        const transform_component = entity.GetComponent(TransformComponent);

        if (entity.HasComponent(QuadComponent)) {
            const quad_component = entity.GetComponent(QuadComponent);
            RenderM.mR2D.DrawQuad(
                transform_component.WorldTransform,
                quad_component.mColor,
                quad_component.mTexCoords,
                0,
                quad_component.mTilingFactor,
            );
        }
        //else if has circle, line, other shapes
    }
}

pub fn RenderSceneLayers(scene_manager: *SceneManager) !void {
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
        scene_manager.FilterEntityByScene(&sprite_entities, scene_id);

        var circle_entities = try ecs_manager.GetGroup(GroupQuery{ .Component = CircleRenderComponent }, allocator);
        scene_manager.FilterEntityByScene(&circle_entities, scene_id);

        //cull entities that shouldnt be rendered
        CullEntities(SpriteRenderComponent, &sprite_entities, scene_manager);
        CullEntities(CircleRenderComponent, &circle_entities, scene_manager);

        //draw sprites
        //first sort and bind textures

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

fn CullEntities(comptime component_type: type, result: *std.ArrayList(Entity.Type), scene_manager: *SceneManager) void {
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

fn TextureSort(comptime component_type: type, entity_list: std.ArrayList(Entity.Type), scene_manager: *SceneManager) !void {
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

fn DrawQuads(quad_entities: std.ArrayList(Entity.Type), scene_manager: *SceneManager) !void {
    for (quad_entities.items) |quad_entity_id| {
        const entity = scene_manager.GetEntity(quad_entity_id);
        const quad_component = entity.GetComponent(QuadComponent);
        const transform_component = entity.GetComponent(TransformComponent);

        RenderM.mR2D.DrawQuad(
            transform_component.GetTransformMatrix(),
            quad_component.mColor,
            quad_component.mTexCoords,
            @floatFromInt(RenderM.mTexturesMap.get(quad_component.mTexture.mID).?),
            quad_component.mTilingFactor,
        );
    }
}

fn DrawSprites(sprite_entities: std.ArrayList(Entity.Type), scene_manager: *SceneManager) !void {
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

fn DrawCircles(circle_entities: std.ArrayList(Entity.Type), scene_manager: *SceneManager) void {
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
