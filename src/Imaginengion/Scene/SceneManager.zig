const std = @import("std");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Mat4f32 = LinAlg.Mat4f32;

const SceneLayer = @import("SceneLayer.zig");
const LayerType = @import("Components/SceneComponent.zig").LayerType;
const SceneSerializer = @import("SceneSerializer.zig");
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const GenUUID = @import("../Core/UUID.zig").GenUUID;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const Entity = @import("../GameObjects/Entity.zig");

const EntityComponents = @import("../GameObjects/Components.zig");
const EntityComponentsArray = EntityComponents.ComponentsList;
const TransformComponent = EntityComponents.TransformComponent;
const CameraComponent = EntityComponents.CameraComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const EntityScriptComponent = EntityComponents.ScriptComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const EntityParentComponent = EntityComponents.ParentComponent;
const EntityChildComponent = EntityComponents.ChildComponent;

const SceneComponents = @import("SceneComponents.zig");
const SceneComponentsList = SceneComponents.ComponentsList;
const SceneComponent = SceneComponents.SceneComponent;
const SceneIDComponent = SceneComponents.IDComponent;
const SceneNameComponent = SceneComponents.NameComponent;
const SceneStackPos = SceneComponents.StackPosComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;

const AssetManager = @import("../Assets/AssetManager.zig");
const Assets = @import("../Assets/Assets.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const ScriptAsset = Assets.ScriptAsset;
const SceneAsset = Assets.SceneAsset;
const ShaderAsset = Assets.ShaderAsset;

const RenderManager = @import("../Renderer/Renderer.zig");
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;

const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const Shader = @import("../Shaders/Shader.zig");

const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;

const SceneManager = @This();

pub const ECSManagerGameObj = ECSManager(Entity.Type, EntityComponentsArray.len);

pub const SceneType = u32;
pub const ECSManagerScenes = ECSManager(SceneType, EntityComponentsArray.len);

pub var SceneManagerGPA = std.heap.DebugAllocator(.{}).init;

//scene stuff
mECSManagerGO: ECSManagerGameObj,
mECSManagerSC: ECSManagerScenes,
mGameLayerInsertIndex: usize,
mNumofLayers: usize,

mViewportWidth: usize,
mViewportHeight: usize,
mViewportFrameBuffer: FrameBuffer,
mViewportVertexArray: VertexArray,
mViewportVertexBuffer: VertexBuffer,
mViewportIndexBuffer: IndexBuffer,
mViewportShaderHandle: AssetHandle,

pub fn Init(width: usize, height: usize, allocator: std.mem.Allocator) !SceneManager {
    const new_scene_manager = SceneManager{
        .mECSManagerGO = try ECSManagerGameObj.Init(SceneManagerGPA.allocator(), &EntityComponentsArray),
        .mECSManagerSC = try ECSManagerScenes.Init(SceneManagerGPA.allocator(), &SceneComponentsList),
        .mGameLayerInsertIndex = 0,
        .mNumofLayers = 0,
        .mViewportWidth = width,
        .mViewportHeight = height,
        .mViewportFrameBuffer = try FrameBuffer.Init(allocator, &[_]TextureFormat{.RGBA8}, .None, 1, false, width, height),
        .mViewportVertexArray = VertexArray.Init(allocator),
        .mViewportVertexBuffer = VertexBuffer.Init(allocator, 4 * @sizeOf(Vec2f32)),
        .mViewportIndexBuffer = undefined,
        .mViewportShaderHandle = try AssetManager.GetAssetHandleRef("assets/shaders/SDFShader.glsl", .Eng),
    };

    const shader_asset = try new_scene_manager.mViewportShaderHandle.GetAsset(ShaderAsset);
    new_scene_manager.mViewportVertexBuffer.SetLayout(shader_asset.mShader.GetLayout());
    new_scene_manager.mViewportVertexBuffer.SetStride(shader_asset.mShader.GetStride());

    var data_index_buffer = [6]u32{ 0, 1, 2, 2, 3, 0 };
    new_scene_manager.mViewportIndexBuffer = IndexBuffer.Init(&data_index_buffer, 6 * @sizeOf(u32));

    var data_vertex_buffer = [4][2]f32{ f32{ -1.0, -1.0 }, f32{ 1.0, -1.0 }, f32{ 1.0, 1.0 }, f32{ -1.0, 1.0 } };
    new_scene_manager.mViewportVertexBuffer.SetData(&data_vertex_buffer[0], @sizeOf([4][2]f32));
    new_scene_manager.mViewportVertexArray.AddVertexBuffer(new_scene_manager.mViewportVertexBuffer);
    new_scene_manager.mViewportVertexArray.SetIndexBuffer(new_scene_manager.mViewportIndexBuffer);

    return new_scene_manager;
}

pub fn Deinit(self: *SceneManager) !void {
    self.mECSManagerGO.Deinit();
    self.mECSManagerSC.Deinit();
    _ = SceneManagerGPA.deinit();
}

pub fn CreateEntity(self: *SceneManager, scene_id: SceneType) !Entity {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    return scene_layer.CreateEntity();
}
pub fn CreateEntityWithUUID(self: *SceneManager, uuid: u128, scene_id: SceneType) !Entity {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    return scene_layer.CreateEntityWithUUID(uuid);
}

pub fn DestroyEntity(self: *SceneManager, e: Entity, scene_id: SceneType) !void {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    scene_layer.DestroyEntity(e);
}
pub fn DuplicateEntity(self: *SceneManager, original_entity: Entity, scene_id: SceneType) !Entity {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    scene_layer.DuplicateEntity(original_entity);
}

pub fn OnViewportResize(self: *SceneManager, width: usize, height: usize) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const camera_group = try self.mECSManagerGO.GetGroup(.{ .Component = CameraComponent }, allocator);
    for (camera_group.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = &self.mECSManagerGO };
        const camera_component = entity.GetComponent(CameraComponent);
        if (camera_component.mIsFixedAspectRatio == false) {
            camera_component.SetViewportSize(width, height);
        }
    }
}

pub fn CalculateTransforms(self: *SceneManager) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const transform_group = try self.mECSManagerGO.GetGroup(.{
        .Not = .{
            .mFirst = GroupQuery{ .Component = TransformComponent },
            .mSecond = GroupQuery{ .Component = EntityChildComponent },
        },
    }, allocator);

    for (transform_group.items) |entity_id| {
        const entity = self.GetEntity(entity_id);
        self.CalculateEntityTransform(entity, LinAlg.Mat4Identity());
    }
}

pub fn NewScene(self: *SceneManager, layer_type: LayerType) !SceneLayer {
    const new_scene_id = try self.mECSManagerSC.CreateEntity();
    const scene_layer = SceneLayer{ .mSceneID = new_scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };

    const new_scene_component = SceneComponent{
        .mFrameBuffer = try FrameBuffer.Init(SceneManagerGPA.allocator(), &[_]TextureFormat{.RGBA8}, .DEPTH24STENCIL8, 1, false, self.mViewportWidth, self.mViewportHeight),
        .mLayerType = layer_type,
    };
    _ = try scene_layer.AddComponent(SceneComponent, new_scene_component);

    _ = try scene_layer.AddComponent(SceneIDComponent, .{ .ID = try GenUUID() });

    const scene_name_component = try scene_layer.AddComponent(SceneNameComponent, .{ .Name = std.ArrayList(u8).init(SceneManagerGPA.allocator()) });
    scene_name_component.Name.clearAndFree();
    _ = try scene_name_component.Name.writer().write("Unsaved Scene");

    try self.InsertScene(scene_layer);

    return scene_layer;
}

pub fn RemoveScene(self: *SceneManager, scene_id: usize) !void {
    self.SaveScene(scene_id);

    const entity_scene_entities = try self.mECSManagerGO.GetGroup(.{ .Component = EntitySceneComponent }, SceneManagerGPA.allocator());
    defer entity_scene_entities.deinit();

    self.FilterEntityByScene(entity_scene_entities, scene_id);

    for (entity_scene_entities.mEntityList.items) |entity_id| {
        self.mECSManagerGO.DestroyEntity(entity_id);
    }

    self.mECSManagerSC.DestroyEntity(scene_id);
}

pub fn LoadScene(self: *SceneManager, path: []const u8) !SceneType {
    const new_scene_id = try self.mECSManagerSC.CreateEntity();
    const scene_layer = SceneLayer{ .mSceneID = new_scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    const scene_asset_handle = try AssetManager.GetAssetHandleRef(path, .Prj);
    const scene_asset = try scene_asset_handle.GetAsset(SceneAsset);

    const new_scene_component = SceneComponent{
        .mSceneAssetHandle = scene_asset_handle,
        .mFrameBuffer = try FrameBuffer.Init(SceneManagerGPA.allocator(), &[_]TextureFormat{.RGBA8}, .DEPTH24STENCIL8, 1, false, self.mViewportWidth, self.mViewportHeight),
        .mLayerType = undefined,
    };

    _ = try scene_layer.AddComponent(SceneComponent, new_scene_component);

    _ = try scene_layer.AddComponent(SceneIDComponent, .{ .ID = undefined });

    const scene_basename = std.fs.path.basename(path);
    const dot_location = std.mem.indexOf(u8, scene_basename, ".") orelse 0;
    const scene_name = scene_basename[0..dot_location];
    var new_scene_name_component = SceneNameComponent{ .Name = std.ArrayList(u8).init(SceneManagerGPA.allocator()) };
    _ = try new_scene_name_component.Name.writer().write(scene_name);

    _ = try scene_layer.AddComponent(SceneNameComponent, new_scene_name_component);

    try SceneSerializer.DeSerializeSceneText(scene_layer, scene_asset);

    try self.InsertScene(scene_layer);

    return new_scene_id;
}
pub fn SaveScene(self: *SceneManager, scene_layer: SceneLayer) !void {
    const scene_component = scene_layer.GetComponent(SceneComponent);
    if (scene_component.mSceneAssetHandle.mID != AssetHandle.NullHandle) {
        try SceneSerializer.SerializeSceneText(scene_layer, scene_component.mSceneAssetHandle);
    } else {
        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const abs_path = try PlatformUtils.SaveFile(fba.allocator(), ".imsc");
        const rel_path = AssetManager.GetRelPath(abs_path);
        _ = try std.fs.createFileAbsolute(abs_path, .{});
        scene_component.mSceneAssetHandle = try AssetManager.GetAssetHandleRef(rel_path, .Prj);
        try self.SaveSceneAs(scene_layer, abs_path);
    }
}
pub fn SaveSceneAs(_: *SceneManager, scene_layer: SceneLayer, abs_path: []const u8) !void {
    const scene_component = scene_layer.GetComponent(SceneComponent);
    const scene_basename = std.fs.path.basename(abs_path);
    const dot_location = std.mem.indexOf(u8, scene_basename, ".") orelse 0;
    const scene_name = scene_basename[0..dot_location];

    const scene_name_component = scene_layer.GetComponent(SceneNameComponent);
    scene_name_component.Name.clearAndFree();
    _ = try scene_name_component.Name.writer().write(scene_name);

    try SceneSerializer.SerializeSceneText(scene_layer, scene_component.mSceneAssetHandle);
}

pub fn MoveScene(self: *SceneManager, scene_id: SceneType, move_to_pos: usize) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const scene_component = self.mECSManagerSC.GetComponent(SceneComponent, scene_id);
    const stack_pos_component = self.mECSManagerSC.GetComponent(SceneStackPos, scene_id);
    const current_pos = stack_pos_component.mPosition;

    var new_pos: usize = 0;
    if (scene_component.mLayerType == .OverlayLayer and move_to_pos < self.mGameLayerInsertIndex) {
        new_pos = self.mGameLayerInsertIndex;
    } else if (scene_component.mLayerType == .GameLayer and move_to_pos >= self.mGameLayerInsertIndex) {
        new_pos = self.mGameLayerInsertIndex - 1;
    } else {
        new_pos = move_to_pos;
    }

    if (new_pos == current_pos) {
        return;
    } else if (new_pos < current_pos) {
        //we are moving the scene down in position so we need to move everything between new_pos and current_pos up 1 position
        const scene_stack_pos_list = try self.mECSManagerSC.GetGroup(.{ .Component = SceneStackPos }, allocator);

        for (scene_stack_pos_list.items) |list_scene_id| {
            const scene_stack_pos_component = self.mECSManagerSC.GetComponent(SceneStackPos, list_scene_id);
            if (scene_stack_pos_component.mPosition >= new_pos and scene_stack_pos_component.mPosition < current_pos) {
                scene_stack_pos_component.mPosition += 1;
            }
        }
    } else {
        //we are moving the scene up in position so we need to move everything between current_pos and new_pos down 1 position
        const scene_stack_pos_list = try self.mECSManagerSC.GetGroup(.{ .Component = SceneStackPos }, allocator);

        for (scene_stack_pos_list.items) |list_scene_id| {
            const scene_stack_pos_component = self.mECSManagerSC.GetComponent(SceneStackPos, list_scene_id);
            if (scene_stack_pos_component.mPosition > current_pos and scene_stack_pos_component.mPosition <= new_pos) {
                scene_stack_pos_component.mPosition -= 1;
            }
        }
    }

    stack_pos_component.mPosition = new_pos;
}

pub fn SaveEntity(self: *SceneManager, entity: Entity) !void {
    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const abs_path = try PlatformUtils.SaveFile(fba.allocator(), ".imsc");
    try self.SaveEntityAs(entity, abs_path);
}

pub fn SaveEntityAs(_: *SceneManager, entity: Entity, abs_path: []const u8) !void {
    try SceneSerializer.SerializeEntityText(entity, abs_path);
}

pub fn FilterEntityByScene(self: *SceneManager, entity_result_list: *std.ArrayList(Entity.Type), scene_id: SceneType) void {
    const scene_layer = SceneLayer(.{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC });
    scene_layer.FilterEntityByScene(entity_result_list);
}

pub fn FilterEntityScriptsByScene(self: *SceneManager, scripts_result_list: *std.ArrayList(Entity.Type), scene_id: SceneType) void {
    const scene_layer = SceneLayer(.{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC });
    scene_layer.FilterEntityScriptsByScene(scripts_result_list);
}

pub fn FilterSceneScriptsByScene(self: *SceneManager, scripts_result_list: *std.ArrayList(Entity.Type), scene_id: SceneType) void {
    const scene_layer = SceneLayer(.{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC });
    scene_layer.FilterSceneScriptsByScene(scripts_result_list);
}

pub fn GetEntityGroup(self: *SceneManager, query: GroupQuery, allocator: std.mem.Allocator) !std.ArrayList(Entity.Type) {
    return try self.mECSManagerGO.GetGroup(query, allocator);
}

pub fn SortScenesFunc(ecs_manager_sc: ECSManagerScenes, a: SceneType, b: SceneType) bool {
    const a_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, a);
    const b_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, b);

    return (b_stack_pos_comp.mPosition < a_stack_pos_comp.mPosition);
}

pub fn GetEntity(self: *SceneManager, entity_id: Entity.Type) Entity {
    return Entity{ .mEntityID = entity_id, .mECSManagerRef = &self.mECSManagerGO };
}

pub fn GetSceneLayer(self: *SceneManager, scene_id: SceneType) SceneLayer {
    return SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
}

fn InsertScene(self: *SceneManager, scene_layer: SceneLayer) !void {
    const scene_component = scene_layer.GetComponent(SceneComponent);
    if (scene_component.mLayerType == .GameLayer) {
        _ = try scene_layer.AddComponent(SceneStackPos, .{ .mPosition = self.mGameLayerInsertIndex });
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const stack_pos_group = try self.mECSManagerSC.GetGroup(.{ .Component = SceneStackPos }, allocator);
        for (stack_pos_group.items) |scene_id| {
            const stack_pos = self.mECSManagerSC.GetComponent(SceneStackPos, scene_id);
            if (stack_pos.mPosition >= self.mGameLayerInsertIndex) {
                stack_pos.mPosition += 1;
            }
        }
        self.mGameLayerInsertIndex += 1;
    } else {
        _ = try scene_layer.AddComponent(SceneStackPos, .{ .mPosition = self.mNumofLayers });
    }
    self.mNumofLayers += 1;
}

fn CalculateEntityTransform(entity: Entity, parent_transform: Mat4f32, parent_dirty: bool) void {
    const transform_component = entity.GetComponent(TransformComponent);
    defer transform_component.Dirty = false;
    if (transform_component.Dirty or parent_dirty) {
        transform_component.WorldTransform = LinAlg.Mat4MulMat4(parent_transform, transform_component.GetLocalTransform());
    }
    if (entity.HasComponent(EntityParentComponent)) {
        const parent_component = entity.GetComponent(EntityParentComponent);

        var curr_id = parent_component.mFirstChild;
        while (curr_id != Entity.NullEntity) {
            const child_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = entity.mECSManagerRef };
            CalculateEntityTransform(child_entity, transform_component.WorldTransform, transform_component.Dirty);

            const child_component = child_entity.GetComponent(EntityChildComponent);
            curr_id = child_component.mNext;
        }
    }
}
