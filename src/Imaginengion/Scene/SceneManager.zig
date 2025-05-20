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
const Components = @import("../GameObjects/Components.zig");
const TransformComponent = Components.TransformComponent;
const CameraComponent = Components.CameraComponent;
const OnInputPressedScript = Components.OnInputPressedScript;
const ScriptComponent = Components.ScriptComponent;
const EntitySceneComponent = Components.SceneIDComponent;
const ComponentsArray = Components.ComponentsList;

const SceneComponents = @import("SceneComponents.zig");
const SceneComponentsList = SceneComponents.ComponentsList;
const SceneComponent = SceneComponents.SceneComponent;
const SceneIDComponent = SceneComponents.IDComponent;
const SceneNameComponent = SceneComponents.NameComponent;
const SceneStackPos = SceneComponents.StackPosComponent;

const AssetManager = @import("../Assets/AssetManager.zig");
const Assets = @import("../Assets/Assets.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const ScriptAsset = Assets.ScriptAsset;
const SceneAsset = Assets.SceneAsset;

const RenderManager = @import("../Renderer/Renderer.zig");
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;

const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const Shader = @import("../Shaders/Shaders.zig");

const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;

const SceneManager = @This();

pub const EntityType = u32;
pub const ECSManagerGameObj = ECSManager(EntityType, ComponentsArray.len);

pub const SceneType = u32;
pub const ECSManagerScenes = ECSManager(SceneType, ComponentsArray.len);

var SceneManagerGPA = std.heap.DebugAllocator(.{}).init;

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
mCompositeShader: Shader,
mNumTexturesUniformBuffer: UniformBuffer,

pub fn Init(width: usize, height: usize) !SceneManager {
    var new_scene_manager = SceneManager{
        //scene stuff
        .mECSManagerGO = try ECSManagerGameObj.Init(SceneManagerGPA.allocator(), &ComponentsArray),
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
        .mCompositeShader = try Shader.Init(SceneManagerGPA.allocator(), "assets/shaders/Composite.glsl"),
        .mNumTexturesUniformBuffer = UniformBuffer.Init(@sizeOf(usize)),
    };

    var data_index_buffer = [6]u32{ 0, 1, 2, 2, 3, 0 };
    new_scene_manager.mCompositeIndexBuffer = IndexBuffer.Init(&data_index_buffer, 6 * @sizeOf(u32));

    try new_scene_manager.mCompositeVertexBuffer.SetLayout(new_scene_manager.mCompositeShader.GetLayout());
    new_scene_manager.mCompositeVertexBuffer.SetStride(new_scene_manager.mCompositeShader.GetStride());

    var data_vertex_buffer = [4]Vec2f32{ Vec2f32{ -1.0, -1.0 }, Vec2f32{ 1.0, -1.0 }, Vec2f32{ 1.0, 1.0 }, Vec2f32{ -1.0, 1.0 } };
    new_scene_manager.mCompositeVertexBuffer.SetData(&data_vertex_buffer[0], 4 * @sizeOf(Vec2f32));

    try new_scene_manager.mCompositeVertexArray.AddVertexBuffer(new_scene_manager.mCompositeVertexBuffer);

    new_scene_manager.mCompositeVertexArray.SetIndexBuffer(new_scene_manager.mCompositeIndexBuffer);

    return new_scene_manager;
}

pub fn Deinit(self: *SceneManager) !void {
    self.mCompositeShader.Deinit();
    self.mCompositeVertexBuffer.Deinit();
    self.mCompositeIndexBuffer.Deinit();
    self.mCompositeVertexArray.Deinit();
    self.mFrameBuffer.Deinit();
    self.mECSManagerGO.Deinit();
    self.mECSManagerSC.Deinit();
    _ = SceneManagerGPA.deinit();
}

pub fn CreateEntity(self: SceneManager, scene_id: usize) !Entity {
    const scene_component = self.mECSManagerSC.GetComponent(SceneComponent, scene_id);
    return scene_component.CreateEntity();
}
pub fn CreateEntityWithUUID(self: SceneManager, uuid: u128, scene_id: usize) !Entity {
    const scene_component = self.mECSManagerSC.GetComponent(SceneComponent, scene_id);
    return scene_component.CreateEntityWithUUID(uuid);
}

pub fn DestroyEntity(self: SceneManager, e: Entity, scene_id: usize) !void {
    const scene_component = self.mECSManagerSC.GetComponent(SceneComponent, scene_id);
    scene_component.DestroyEntity(e);
}
pub fn DuplicateEntity(self: SceneManager, original_entity: Entity, scene_id: usize) !Entity {
    const scene_component = self.mECSManagerSC.GetComponent(SceneComponent, scene_id);
    scene_component.DuplicateEntity(original_entity);
}

pub fn OnViewportResize(self: *SceneManager, width: usize, height: usize) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const scene_group = try self.mECSManagerSC.GetGroup(.{ .Component = SceneComponent }, allocator);
    for (scene_group.items) |scene_id| {
        const scene_component = self.mECSManagerSC.GetComponent(SceneComponent, scene_id);
        scene_component.OnViewportResize(width, height);
    }
}

pub fn NewScene(self: *SceneManager, layer_type: LayerType) !SceneType {
    const new_scene_id = try self.mECSManagerSC.CreateEntity();
    const scene_layer = SceneLayer{ .mSceneID = new_scene_id, .mECSManagerSCRef = &self.mECSManagerSC };

    const new_scene_component = SceneComponent{
        .mFrameBuffer = try FrameBuffer.Init(SceneManagerGPA.allocator(), &[_]TextureFormat{.RGBA8}, .DEPTH24STENCIL8, 1, false, self.mViewportWidth, self.mViewportHeight),
        .mLayerType = layer_type,
        .mECSManagerRef = self.mECSManagerGO,
    };
    _ = try scene_layer.AddComponent(SceneComponent, new_scene_component);

    _ = try scene_layer.AddComponent(SceneIDComponent, .{ .ID = try GenUUID() });

    self.InsertScene(scene_layer);
}

pub fn RemoveScene(self: *SceneManager, scene_id: usize) !void {
    self.SaveScene(scene_id);

    const entity_scene_entities = try self.mECSManagerGO.GetGroup(.{ .Component = EntitySceneComponent });

    self.FilterByScene(entity_scene_entities, scene_id);

    for (entity_scene_entities.mEntityList.items) |entity_id| {
        self.mECSManagerGO.DestroyEntity(entity_id);
    }

    self.mECSManagerSC.DestroyEntity(scene_id);
}

pub fn LoadScene(self: *SceneManager, path: []const u8) !SceneType {
    const new_scene_id = try self.mECSManagerSC.CreateEntity();
    const scene_layer = SceneLayer{ .mSceneID = new_scene_id, .mECSManagerSCRef = &self.mECSManagerSC };
    const scene_asset_handle = try AssetManager.GetAssetHandleRef(path, .Prj);
    const scene_asset = try scene_asset_handle.GetAsset(SceneAsset);

    const new_scene_component = SceneComponent{
        .mSceneAssetHandle = scene_asset_handle,
        .mFrameBuffer = try FrameBuffer.Init(SceneManagerGPA.allocator(), &[_]TextureFormat{.RGBA8}, .DEPTH24STENCIL8, 1, false, self.mViewportWidth, self.mViewportHeight),
        .mLayerType = undefined,
        .mECSManagerRef = self.mECSManagerGO,
    };

    _ = try scene_layer.AddComponent(SceneComponent, new_scene_component);

    _ = try scene_layer.AddComponent(SceneIDComponent, .{ .ID = undefined });

    try SceneSerializer.DeSerializeText(scene_layer, scene_asset);

    try self.InsertScene(&scene_layer);

    return new_scene_id;
}
pub fn SaveScene(self: *SceneManager, scene_id: usize) !void {
    //TODO: convert to new scene system
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerSCRef = &self.mECSManagerSC };
    const scene_component = scene_layer.GetComponent(SceneComponent, scene_id);
    if (scene_component.mSceneAssetHandle.mID != AssetHandle.NullHandle) {
        try SceneSerializer.SerializeText(scene_layer);
    } else {
        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const path = try PlatformUtils.SaveFile(fba.allocator(), ".imsc");
        self.SaveSceneAs(scene_id, path);
        scene_component.mSceneAssetHandle = AssetManager.GetAssetHandleRef(path, .Abs);
    }
}
pub fn SaveSceneAs(self: *SceneManager, scene_id: usize, path: []const u8) !void {
    //TODO: convert to new scene system
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerSCRef = &self.mECSManagerSC };

    const scene_basename = std.fs.path.basename(path);
    const dot_location = std.mem.indexOf(u8, scene_basename, ".") orelse 0;
    const scene_name = scene_basename[0..dot_location];

    scene_layer.mName.clearAndFree();
    _ = try scene_layer.mName.writer().write(scene_name);
    scene_layer.mPath.clearAndFree();
    _ = try scene_layer.mPath.writer().write(path);

    try SceneSerializer.SerializeText(scene_layer);
}

pub fn MoveScene(self: *SceneManager, scene_id: usize, move_to_pos: usize) void {
    //TODO: convert to new scene system
    const current_scene = self.mSceneStack.items[scene_id];
    const current_pos = scene_id;

    var new_pos: usize = 0;
    if (current_scene.mLayerType == .OverlayLayer and move_to_pos < self.mLayerInsertIndex) {
        new_pos = self.mLayerInsertIndex;
    } else if (current_scene.mLayerType == .GameLayer and move_to_pos >= self.mLayerInsertIndex) {
        new_pos = self.mLayerInsertIndex - 1;
    } else {
        new_pos = move_to_pos;
    }

    if (new_pos < current_pos) {
        std.mem.copyBackwards(SceneLayer, self.mSceneStack.items[new_pos + 1 .. current_pos + 1], self.mSceneStack.items[new_pos..current_pos]);

        for (self.mSceneStack.items[new_pos + 1 .. current_pos + 1]) |*scene_layer| {
            scene_layer.mInternalID += 1;
        }
    } else {
        std.mem.copyForwards(SceneLayer, self.mSceneStack.items[current_pos..new_pos], self.mSceneStack.items[current_pos + 1 .. new_pos + 1]);

        for (self.mSceneStack.items[current_pos..new_pos]) |*scene_layer| {
            scene_layer.mInternalID -= 1;
        }
    }
    self.mSceneStack.items[new_pos] = current_scene;
    self.mSceneStack.items[new_pos].mInternalID = new_pos;
}

pub fn FilterByScene(self: *SceneManager, result_list: *std.ArrayList(EntityType), scene_id: SceneType) void {
    if (result_list.items.len == 0) return;

    var end_index: usize = result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const entity_scene_component = self.mECSManagerGO.GetComponent(EntitySceneComponent, result_list[i]);
        if (entity_scene_component.SceneID != scene_id) {
            result_list.items[i] = result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    result_list.shrinkAndFree(end_index);
}

fn InsertScene(self: *SceneManager, scene_layer: SceneLayer) !void {
    const scene_component = scene_layer.GetComponent(SceneComponent);
    if (scene_component.mLayerType == .GameLayer) {
        scene_layer.AddComponent(SceneStackPos, .{ .mPosition = self.mGameLayerInsertIndex });
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
        scene_layer.AddComponent(SceneStackPos, .{ .mPosition = self.mNumofLayers });
    }
    self.mNumofLayers += 1;
}
