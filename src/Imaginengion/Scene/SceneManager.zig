const std = @import("std");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Mat4f32 = LinAlg.Mat4f32;

const SceneLayer = @import("SceneLayer.zig");
const LayerType = SceneLayer.LayerType;
const SceneSerializer = @import("SceneSerializer.zig");
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");

const ECSManager = @import("../ECS/ECSManager.zig");
const Entity = @import("..//GameObjects/Entity.zig");
const Components = @import("../GameObjects/Components.zig");
const TransformComponent = Components.TransformComponent;
const CameraComponent = Components.CameraComponent;
const OnKeyPressedScript = Components.OnKeyPressedScript;
const ScriptComponent = Components.ScriptComponent;
const ComponentsArray = Components.ComponentsList;

const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;

const RenderManager = @import("../Renderer/Renderer.zig");
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const InternalFrameBuffer = @import("../FrameBuffers/InternalFrameBuffer.zig").FrameBuffer;
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;

const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const Shader = @import("../Shaders/Shaders.zig");

const KeyPressedEvent = @import("../Events/SystemEvent.zig").KeyPressedEvent;

const SceneManager = @This();

pub const ESceneState = enum {
    Stop,
    Play,
};

var SceneManagerGPA = std.heap.DebugAllocator(.{}).init;

mSceneStack: std.ArrayList(SceneLayer),
mECSManager: ECSManager,
mSceneState: ESceneState,
mLayerInsertIndex: usize,
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
        .mSceneStack = std.ArrayList(SceneLayer).init(SceneManagerGPA.allocator()),
        .mECSManager = try ECSManager.Init(SceneManagerGPA.allocator(), &ComponentsArray),
        .mSceneState = .Stop,
        .mLayerInsertIndex = 0,
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
    var iter = std.mem.reverseIterator(self.mSceneStack.items);
    while (iter.next()) |scene_layer| {
        try self.RemoveScene(scene_layer.mInternalID);
    }
    self.mSceneStack.deinit();
    self.mCompositeShader.Deinit();
    self.mCompositeVertexBuffer.Deinit();
    self.mCompositeIndexBuffer.Deinit();
    self.mCompositeVertexArray.Deinit();
    self.mFrameBuffer.Deinit();
    self.mECSManager.Deinit();
    _ = SceneManagerGPA.deinit();
}

pub fn CreateEntity(self: SceneManager, scene_id: usize) !Entity {
    std.debug.assert(scene_id < self.mSceneStack.items.len);
    return self.mSceneStack.items[scene_id].CreateEntity();
}
pub fn CreateEntityWithUUID(self: SceneManager, uuid: u128, scene_id: usize) !Entity {
    std.debug.assert(scene_id < self.mSceneStack.items.len);
    return self.mSceneStack.items[scene_id].CreateEntityWithUUID(uuid);
}

pub fn DestroyEntity(self: SceneManager, e: Entity, scene_id: usize) !void {
    std.debug.assert(scene_id < self.mSceneStack.items.len);
    self.mSceneStack.items[scene_id].DestroyEntity(e.EntityID);
}
pub fn DuplicateEntity(self: SceneManager, original_entity: Entity, scene_id: usize) !Entity {
    std.debug.assert(scene_id < self.mSceneStack.items.len);
    return self.mSceneStack.items[scene_id].DuplicateEntity(original_entity.EntityID);
}

pub fn RenderUpdate(self: *SceneManager, camera_id: u32) !void {
    const camera_component = self.mECSManager.GetComponent(CameraComponent, camera_id);
    const camera_transform = self.mECSManager.GetComponent(TransformComponent, camera_id);

    //render each scene
    const camera_view_projection = LinAlg.Mat4MulMat4(camera_component.mProjection, LinAlg.Mat4Inverse(camera_transform.GetTransformMatrix()));
    RenderManager.BeginRendering(camera_view_projection);

    for (self.mSceneStack.items) |scene_layer| {
        try scene_layer.Render(); //this renders each scene_layer to its own frame buffer
    }
    self.mNumTexturesUniformBuffer.SetData(&self.mSceneStack.items.len, @sizeOf(usize), 0);
    self.mFrameBuffer.Bind();
    self.mFrameBuffer.ClearFrameBuffer(.{ 0.3, 0.3, 0.3, 1.0 });
    self.mNumTexturesUniformBuffer.Bind(0);
    self.mCompositeShader.Bind();
    for (self.mSceneStack.items, 0..) |scene_layer, i| {
        scene_layer.mFrameBuffer.BindColorAttachment(0, i);
        scene_layer.mFrameBuffer.BindDepthAttachment(i + self.mSceneStack.items.len);
    }

    RenderManager.DrawComposite(self.mCompositeVertexArray);

    self.mFrameBuffer.Unbind();
}

pub fn OnKeyPressedEvent(self: *SceneManager, e: KeyPressedEvent) !bool {
    //get all of the entities with key pressed event scripts and call the run function on them
    //also it has to go from the top layer to the bottom layer that way if a layer blocks the key press it wont go to the lower layers
    //which means i will have to call filter on the group starting from the top most scene stack itemand work backwards
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const key_pressed_script_group = try self.mECSManager.GetGroup(.{ .Component = OnKeyPressedScript }, allocator);

    for (group.items) |script_id| {
        const script_component = self.mECSManager.GetComponent(ScriptComponent, script_id);
        const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);

        const run_func = script_asset.mLib.lookup(*const fn (*std.mem.Allocator, *Entity, *KeyPressedEvent) anyerror!void, "Run").?;
        run_func(allocator, script_component.mParent, e);
    }
    return false;
}

pub fn OnViewportResize(self: *SceneManager, width: usize, height: usize) !void {
    self.mViewportWidth = width;
    self.mViewportHeight = height;
    self.mFrameBuffer.Resize(width, height);
    for (self.mSceneStack.items) |*scene_layer| {
        try scene_layer.OnViewportResize(width, height);
    }
}

pub fn NewScene(self: *SceneManager, layer_type: LayerType) !usize {
    var new_scene = try SceneLayer.Init(SceneManagerGPA.allocator(), layer_type, std.math.maxInt(usize), self.mViewportWidth, self.mViewportHeight, &self.mECSManager);
    _ = try new_scene.mName.writer().write("Unsaved Scene");

    try self.InsertScene(&new_scene);

    return new_scene.mInternalID;
}
pub fn RemoveScene(self: *SceneManager, scene_id: usize) !void {
    std.debug.assert(scene_id < self.mSceneStack.items.len);
    const scene_layer = &self.mSceneStack.items[scene_id];
    try self.SaveScene(scene_id);
    scene_layer.Deinit();
    _ = self.mSceneStack.orderedRemove(scene_id);
}

pub fn LoadScene(self: *SceneManager, path: []const u8) !usize {
    var new_scene = try SceneLayer.Init(SceneManagerGPA.allocator(), .GameLayer, self.mSceneStack.items.len, self.mViewportWidth, self.mViewportHeight, &self.mECSManager);

    const scene_basename = std.fs.path.basename(path);
    const dot_location = std.mem.indexOf(u8, scene_basename, ".") orelse 0;
    const scene_name = scene_basename[0..dot_location];

    new_scene.mName.clearAndFree();
    _ = try new_scene.mName.writer().write(scene_name);
    new_scene.mPath.clearAndFree();
    _ = try new_scene.mPath.writer().write(path);

    try SceneSerializer.DeSerializeText(&new_scene);

    try self.InsertScene(&new_scene);

    return new_scene.mInternalID;
}
pub fn SaveScene(self: *SceneManager, scene_id: usize) !void {
    std.debug.assert(scene_id < self.mSceneStack.items.len);
    const scene_layer = &self.mSceneStack.items[scene_id];
    if (scene_layer.mPath.items.len != 0) {
        try SceneSerializer.SerializeText(scene_layer);
    } else {
        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const path = try PlatformUtils.SaveFile(fba.allocator(), ".imsc");
        if (path.len > 0) try self.SaveSceneAs(scene_id, path);
    }
}
pub fn SaveSceneAs(self: *SceneManager, scene_id: usize, path: []const u8) !void {
    std.debug.assert(scene_id < self.mSceneStack.items.len);
    const scene_layer = &self.mSceneStack.items[scene_id];

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

fn InsertScene(self: *SceneManager, scene_layer: *SceneLayer) !void {
    if (scene_layer.mLayerType == .OverlayLayer) {
        scene_layer.mInternalID = self.mSceneStack.items.len;
        try self.mSceneStack.append(scene_layer.*);
    } else {
        scene_layer.mInternalID = self.mLayerInsertIndex;
        try self.mSceneStack.insert(self.mLayerInsertIndex, scene_layer.*);
        self.mLayerInsertIndex += 1;
        for (self.mSceneStack.items[self.mLayerInsertIndex..]) |*changed_scene_layer| {
            changed_scene_layer.mInternalID += 1;
        }
    }
}

fn FilterSceneUUID(group: *std.ArrayList(u32), scene_uuid: u128, ecs_manager, *ECSManager, allocator: std.mem.Allocator) std.ArrayList(u32) {
    //create a new group based on the input group which is a member of a specific scene

}
