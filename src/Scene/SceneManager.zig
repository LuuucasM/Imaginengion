const std = @import("std");
const Vec2f32 = @import("../Math/LinAlg.zig").Vec2f32;
const Mat4f32 = @import("../Math/LinAlg.zig").Mat4f32;

const SceneLayer = @import("SceneLayer.zig");
const LayerType = SceneLayer.LayerType;
const SceneSerializer = @import("SceneSerializer.zig");
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");

const ECSManager = @import("../ECS/ECSManager.zig");
const Entity = @import("..//GameObjects/Entity.zig");
const Components = @import("../GameObjects/Components.zig");
const ComponentsArray = Components.ComponentsList;

const RenderManager = @import("../Renderer/Renderer.zig");
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const InternalFrameBuffer = @import("../FrameBuffers/InternalFrameBuffer.zig").FrameBuffer;
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;

const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const Shader = @import("../Shaders/Shaders.zig");

const SceneManager = @This();

pub const ESceneState = enum {
    Stop,
    Play,
};

var SceneManagerGPA: std.heap.GeneralPurposeAllocator(.{}) = .{};

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
        .mECSManager = try ECSManager.Init(SceneManagerGPA.allocator(), &ComponentsArray, &[_]type{}),
        .mSceneState = .Stop,
        .mLayerInsertIndex = 0,
        .mViewportWidth = width,
        .mViewportHeight = height,
        .mFrameBuffer = try FrameBuffer.Init(SceneManagerGPA.allocator(), InternalFrameBuffer(&[_]TextureFormat{.RGBA8}, .None, 1, false), width, height),

        .mCompositeVertexArray = VertexArray.Init(SceneManagerGPA.allocator()),
        .mCompositeVertexBuffer = VertexBuffer.Init(SceneManagerGPA.allocator(), 4 * @sizeOf(Vec2f32)),
        .mCompositeIndexBuffer = undefined,
        .mCompositeShader = try Shader.Init(SceneManagerGPA.allocator(), "assets/shaders/Composite.glsl"),
        .mNumTexturesUniformBuffer = UniformBuffer.Init(@sizeOf(usize)),
    };

    var data_index_buffer = [6]u32{ 0, 1, 2, 2, 3, 0 };
    new_scene_manager.mCompositeIndexBuffer = IndexBuffer.Init(&data_index_buffer, 6);

    try new_scene_manager.mCompositeVertexBuffer.SetLayout(new_scene_manager.mCompositeShader.GetLayout());
    new_scene_manager.mCompositeVertexBuffer.SetStride(new_scene_manager.mCompositeShader.GetStride());

    const data_vertex_buffer = [4]Vec2f32{ Vec2f32{ -1.0, -1.0 }, Vec2f32{ 1.0, -1.0 }, Vec2f32{ 1.0, 1.0 }, Vec2f32{ -1.0, 1.0 } };
    new_scene_manager.mCompositeVertexBuffer.SetData(@constCast(&data_vertex_buffer[0]), 4 * @sizeOf(Vec2f32));

    try new_scene_manager.mCompositeVertexArray.AddVertexBuffer(new_scene_manager.mCompositeVertexBuffer);

    new_scene_manager.mCompositeVertexArray.SetIndexBuffer(new_scene_manager.mCompositeIndexBuffer);

    new_scene_manager.mNumTexturesUniformBuffer.Bind(0);
    new_scene_manager.mCompositeShader.Bind();

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

//pub fn OnRuntimeStart() void {}
//pub fn OnRuntimeStop() void{}
//pub fn OnUpdateRuntime() void {}

pub fn RenderUpdate(self: *SceneManager, camera_projection: Mat4f32, camera_transform: Mat4f32) !void {
    //render each scene
    RenderManager.BeginRendering(camera_projection, camera_transform);

    for (self.mSceneStack.items) |scene_layer| {
        try scene_layer.Render(); //this renders each scene_layer to its own frame buffer
    }

    self.mFrameBuffer.Bind();
    self.mFrameBuffer.ClearFrameBuffer(.{ 0.8, 0.8, 0.0, 1.0 });
    self.mCompositeShader.Bind();

    var i: usize = 0;
    for (self.mSceneStack.items) |scene_layer| {
        scene_layer.mFrameBuffer.BindColorAttachment(0, i);
        i += 1;
    }

    self.mNumTexturesUniformBuffer.SetData(&i, @sizeOf(usize), 0);

    for (self.mSceneStack.items) |scene_layer| {
        scene_layer.mFrameBuffer.BindDepthAttachment(i);
        i += 1;
    }

    RenderManager.DrawComposite(self.mCompositeVertexArray);

    //make a draw call
    self.mFrameBuffer.Unbind();
}

//pub fn SetSceneName() void {}
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
