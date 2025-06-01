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
const Entity = @import("../GameObjects/Entity.zig");

const EntityComponents = @import("../GameObjects/Components.zig");
const EntityComponentsArray = EntityComponents.ComponentsList;
const TransformComponent = EntityComponents.TransformComponent;
const CameraComponent = EntityComponents.CameraComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const EntityScriptComponent = EntityComponents.ScriptComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;

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

pub const EntityType = u32;
pub const ECSManagerGameObj = ECSManager(EntityType, EntityComponentsArray.len);

pub const SceneType = u32;
pub const ECSManagerScenes = ECSManager(SceneType, EntityComponentsArray.len);

pub var SceneManagerGPA = std.heap.DebugAllocator(.{}).init;

//scene stuff
mECSManagerGO: ECSManagerGameObj,
mECSManagerSC: ECSManagerScenes,
mGameLayerInsertIndex: usize,
mNumofLayers: usize,

//render stuff
mFrameBuffer: FrameBuffer,
mViewportWidth: usize,
mViewportHeight: usize,
mCompositeVertexArray: VertexArray,
mCompositeVertexBuffer: VertexBuffer,
mCompositeIndexBuffer: IndexBuffer,
mCompositeShaderHandle: AssetHandle,
mNumTexturesUniformBuffer: UniformBuffer,

pub fn Init(width: usize, height: usize) !SceneManager {
    var new_scene_manager = SceneManager{
        //scene stuff
        .mECSManagerGO = try ECSManagerGameObj.Init(SceneManagerGPA.allocator(), &EntityComponentsArray),
        .mECSManagerSC = try ECSManagerScenes.Init(SceneManagerGPA.allocator(), &SceneComponentsList),
        .mGameLayerInsertIndex = 0,
        .mNumofLayers = 0,

        //render stuff
        .mViewportWidth = width,
        .mViewportHeight = height,
        .mFrameBuffer = try FrameBuffer.Init(SceneManagerGPA.allocator(), &[_]TextureFormat{.RGBA8}, .None, 1, false, width, height),
        .mCompositeVertexArray = VertexArray.Init(SceneManagerGPA.allocator()),
        .mCompositeVertexBuffer = VertexBuffer.Init(SceneManagerGPA.allocator(), 4 * @sizeOf(Vec2f32)),
        .mCompositeIndexBuffer = undefined,
        .mCompositeShaderHandle = try AssetManager.GetAssetHandleRef("assets/shaders/Composite.glsl", .Eng),
        .mNumTexturesUniformBuffer = UniformBuffer.Init(@sizeOf(usize)),
    };

    var data_index_buffer = [6]u32{ 0, 1, 2, 2, 3, 0 };
    new_scene_manager.mCompositeIndexBuffer = IndexBuffer.Init(&data_index_buffer, 6 * @sizeOf(u32));

    const shader_asset = try new_scene_manager.mCompositeShaderHandle.GetAsset(ShaderAsset);

    try new_scene_manager.mCompositeVertexBuffer.SetLayout(shader_asset.mShader.GetLayout());
    new_scene_manager.mCompositeVertexBuffer.SetStride(shader_asset.mShader.GetStride());

    var data_vertex_buffer = [4]Vec2f32{ Vec2f32{ -1.0, -1.0 }, Vec2f32{ 1.0, -1.0 }, Vec2f32{ 1.0, 1.0 }, Vec2f32{ -1.0, 1.0 } };
    new_scene_manager.mCompositeVertexBuffer.SetData(&data_vertex_buffer[0], 4 * @sizeOf(Vec2f32));

    try new_scene_manager.mCompositeVertexArray.AddVertexBuffer(new_scene_manager.mCompositeVertexBuffer);

    new_scene_manager.mCompositeVertexArray.SetIndexBuffer(new_scene_manager.mCompositeIndexBuffer);

    return new_scene_manager;
}

pub fn Deinit(self: *SceneManager) !void {
    AssetManager.ReleaseAssetHandleRef(&self.mCompositeShaderHandle);
    self.mCompositeVertexBuffer.Deinit();
    self.mCompositeIndexBuffer.Deinit();
    self.mCompositeVertexArray.Deinit();
    self.mFrameBuffer.Deinit();
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

pub fn NewScene(self: *SceneManager, layer_type: LayerType) !SceneType {
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

    return new_scene_id;
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

    try SceneSerializer.DeSerializeText(scene_layer, scene_asset);

    try self.InsertScene(scene_layer);

    return new_scene_id;
}
pub fn SaveScene(self: *SceneManager, scene_id: SceneType) !void {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    const scene_component = scene_layer.GetComponent(SceneComponent);
    if (scene_component.mSceneAssetHandle.mID != AssetHandle.NullHandle) {
        try SceneSerializer.SerializeText(scene_layer, scene_component.mSceneAssetHandle);
    } else {
        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const path = try PlatformUtils.SaveFile(fba.allocator(), ".imsc");
        try self.SaveSceneAs(scene_id, path);
        scene_component.mSceneAssetHandle = try AssetManager.GetAssetHandleRef(path, .Abs);
    }
}
pub fn SaveSceneAs(self: *SceneManager, scene_id: SceneType, path: []const u8) !void {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    const scene_component = scene_layer.GetComponent(SceneComponent);
    const scene_basename = std.fs.path.basename(path);
    const dot_location = std.mem.indexOf(u8, scene_basename, ".") orelse 0;
    const scene_name = scene_basename[0..dot_location];

    const scene_name_component = scene_layer.GetComponent(SceneNameComponent);
    scene_name_component.Name.clearAndFree();
    _ = try scene_name_component.Name.writer().write(scene_name);

    try SceneSerializer.SerializeText(scene_layer, scene_component.mSceneAssetHandle);
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

pub fn FilterEntityByScene(self: *SceneManager, entity_result_list: *std.ArrayList(EntityType), scene_id: SceneType) void {
    if (entity_result_list.items.len == 0) return;

    var end_index: usize = entity_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const entity_scene_component = self.mECSManagerGO.GetComponent(EntitySceneComponent, entity_result_list.items[i]);
        if (entity_scene_component.SceneID != scene_id) {
            entity_result_list.items[i] = entity_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    entity_result_list.shrinkAndFree(end_index);
}

pub fn FilterEntityScriptsByScene(self: *SceneManager, scripts_result_list: *std.ArrayList(EntityType), scene_id: SceneType) void {
    if (scripts_result_list.items.len == 0) return;

    var end_index: usize = scripts_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const entity_script_component = self.mECSManagerGO.GetComponent(EntityScriptComponent, scripts_result_list.items[i]);
        const parent_scene_component = self.mECSManagerGO.GetComponent(EntitySceneComponent, entity_script_component.mParent);
        if (parent_scene_component.SceneID != scene_id) {
            scripts_result_list.items[i] = scripts_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    scripts_result_list.shrinkAndFree(end_index);
}

pub fn FilterSceneScriptsByScene(self: *SceneManager, scripts_result_list: *std.ArrayList(EntityType), scene_id: SceneType) void {
    if (scripts_result_list.items.len == 0) return;

    var end_index: usize = scripts_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const scene_script_component = self.mECSManagerSC.GetComponent(SceneScriptComponent, scripts_result_list.items[i]);
        if (scene_script_component.mParent != scene_id) {
            scripts_result_list.items[i] = scripts_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    scripts_result_list.shrinkAndFree(end_index);
}

pub fn SortScenesFunc(ecs_manager_sc: ECSManagerScenes, a: SceneType, b: SceneType) bool {
    const a_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, a);
    const b_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, b);

    return (b_stack_pos_comp.mPosition < a_stack_pos_comp.mPosition);
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
