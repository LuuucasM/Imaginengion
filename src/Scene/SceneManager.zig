const std = @import("std");
const LinAlg = @import("../Math/LinAlg.zig");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const LayerType = @import("../ECS/Components/SceneIDComponent.zig").ELayerType;
const ECSManager = @import("../ECS/ECSManager.zig");
const Entity = @import("../ECS/Entity.zig");
const FrameBufferFile = @import("../FrameBuffers/FrameBuffer.zig");
const FrameBuffer = FrameBufferFile.FrameBuffer;
const TextureFormat = FrameBufferFile.TextureFormat;
const SceneLayer = @import("SceneLayer.zig");
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const SceneSerializer = @import("SceneSerializer.zig");
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const SceneManager = @This();

const Components = @import("../ECS/Components.zig");
const IDComponent = Components.IDComponent;
const SceneIDComponent = Components.SceneIDComponent;
const NameComponent = Components.NameComponent;
const TransformComponent = Components.TransformComponent;

pub const ESceneState = enum {
    Stop,
    Play,
};

var NextID: u8 = 0;

var SceneManagerGPA: std.heap.GeneralPurposeAllocator(.{}) = .{};

mFrameBuffer: FrameBuffer(&[_]TextureFormat{ .RGBA8, .RED_INTEGER }, .DEPTH24STENCIL8, 1, false),
mSceneStack: SparseSet(.{
    .SparseT = u128,
    .DenseT = u8,
    .ValueT = SceneLayer,
    .allow_resize = .ResizeAllowed,
    .value_layout = .InternalArrayOfStructs,
}),
mECSManager: ECSManager,
mSceneState: ESceneState,
mDeletedSceneIDs: std.ArrayList(u8),

pub fn Init(width: usize, height: usize) !SceneManager {
    return SceneManager{
        .mFrameBuffer = FrameBuffer(&[_]TextureFormat{ .RGBA8, .RED_INTEGER }, .DEPTH24STENCIL8, 1, false).Init(width, height),
        .mSceneStack = try SparseSet(.{
            .SparseT = u128,
            .DenseT = u8,
            .ValueT = SceneLayer,
            .allow_resize = .ResizeAllowed,
            .value_layout = .InternalArrayOfStructs,
        }).init(SceneManagerGPA.allocator(), 16, 16),
        .mECSManager = try ECSManager.Init(SceneManagerGPA.allocator()),
        .mSceneState = .Stop,
        .mDeletedSceneIDs = std.ArrayList(u8).init(SceneManagerGPA.allocator()),
    };
}

pub fn Deinit(self: *SceneManager) !void {
    var iter = std.mem.reverseIterator(self.mSceneStack.values[0..self.mSceneStack.dense_count]);
    while (iter.next()) |scene_layer| {
        try self.RemoveScene(scene_layer.mInternalID);
    }
    self.mSceneStack.deinit();
    self.mFrameBuffer.Deinit();
    self.mECSManager.Deinit();
    self.mDeletedSceneIDs.deinit();
    _ = SceneManagerGPA.deinit();
}

pub fn CreateEntity(self: SceneManager, name: [24]u8, scene_id: u8) !Entity {
    std.debug.assert(self.mSceneStack.hasSparse(scene_id) == true);
    return self.CreateEntityWithUUID(name, GenUUID(), scene_id);
}
pub fn CreateEntityWithUUID(self: SceneManager, name: [24]u8, uuid: u128, scene_id: u8) !Entity {
    std.debug.assert(self.mSceneStack.hasSparse(scene_id) == true);
    const scene_layer = self.mSceneStack.getValueBySparse(scene_id).*;
    const e = Entity{ .mEntityID = try self.mECSManager.CreateEntity(), .mLayerType = scene_layer.mLayerType, .mECSManager = &self.mECSManager };
    _ = e.AddComponent(IDComponent, .{ .ID = uuid });
    _ = e.AddComponent(SceneIDComponent, .{ .ID = scene_layer.mUUID, .LayerType = scene_layer.mLayerType });
    _ = e.AddComponent(NameComponent, .{ .Name = name });
    _ = e.AddComponent(TransformComponent, .{ .Transform = LinAlg.InitMat4CompTime(1.0) });

    scene_layer.mEntities.add(e.mEntityID);

    return e;
}

pub fn DestroyEntity(self: SceneManager, e: Entity, scene_id: u8) !void {
    std.debug.assert(self.mSceneStack.hasSparse(scene_id) == true);
    const scene_layer = self.mSceneStack.getValueBySparse(scene_id).*;
    try self.mECSManager.DestroyEntity(e.mEntityID);
    scene_layer.mEntities.remove(e.mEntityID);
}
pub fn DuplicateEntity(self: SceneManager, original_entity: Entity, scene_id: u8) !Entity {
    std.debug.assert(self.mSceneStack.hasSparse(scene_id) == true);
    const scene_layer = self.mSceneStack.getValueBySparse(scene_id).*;
    const new_entity = Entity{ .mEntityID = try self.mECSManager.DuplicateEntity(original_entity.mEntityID), .mECSManager = &self.mECSManager };
    scene_layer.mEntities.add(new_entity.mEntityID);
    return new_entity;
}

//pub fn OnRuntimeStart() void {}
//pub fn OnRuntimeStop() void{}
//pub fn OnUpdateRuntime() void {}
//pub fn OnUpdateEditor() void {}
//pub fn OnEvent() void {}
//pub fn SetSceneName() void {}
//fn OnViewportResize void {}

pub fn NewScene(self: *SceneManager, layer_type: LayerType) !void {
    var new_id: u8 = 0;
    if (self.mDeletedSceneIDs.items.len > 0) {
        new_id = self.mDeletedSceneIDs.pop();
    } else {
        new_id = NextID;
        NextID += 1;
    }

    var new_scene = try SceneLayer.Init(SceneManagerGPA.allocator(), layer_type, new_id);
    _ = self.mSceneStack.addValue(new_id, new_scene);

    _ = try new_scene.mName.writer().write("Unsaved Scene");
}
pub fn RemoveScene(self: *SceneManager, scene_id: u8) !void {
    std.debug.assert(self.mSceneStack.hasSparse(scene_id) == true);
    const scene_layer = self.mSceneStack.getValueBySparse(scene_id);
    if (scene_layer.mPath.items.len == 0) {
        try self.SaveScene(scene_id);
    } else {
        try self.SaveSceneAs(scene_id);
    }
    scene_layer.Deinit();
    self.mSceneStack.orderedRemove(scene_id);
    try self.mDeletedSceneIDs.append(scene_id);
}
pub fn LoadScene(self: SceneManager) void {
    _ = self;
    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const path = try PlatformUtils.OpenFile(fba.allocator(), "imsc");
    std.debug.print("LOADING SCENE NEEDS TO BE IMPLEMENTED: {s}", .{path});
    //const new_scene = scene deserialize(path)
    //self.mSceneStack.append(new_scene)
}
pub fn SaveScene(self: *SceneManager, scene_id: u8) !void {
    std.debug.assert(self.mSceneStack.hasSparse(scene_id) == true);
    const scene_layer = self.mSceneStack.getValueBySparse(scene_id).*;
    if (scene_layer.mPath.items.len != 0) {
        try SceneSerializer.SerializeText(scene_layer, self);
    } else {
        try self.SaveSceneAs(scene_id);
    }
}
pub fn SaveSceneAs(self: *SceneManager, scene_id: u8) !void {
    std.debug.assert(self.mSceneStack.hasSparse(scene_id) == true);
    const scene_layer = self.mSceneStack.getValueBySparse(scene_id);

    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const path = try PlatformUtils.SaveFile(fba.allocator(), "imsc");
    if (path.len > 0) {
        const scene_basename = std.fs.path.basename(path);
        const dot_location = std.mem.indexOf(u8, scene_basename, ".") orelse 0;
        const scene_name = scene_basename[0..dot_location];
        scene_layer.mName.clearAndFree();
        _ = try scene_layer.mName.writer().write(scene_name);
        scene_layer.mPath.clearAndFree();
        _ = try scene_layer.mPath.writer().write(path);
        try SceneSerializer.SerializeText(scene_layer.*, self);
    }
}
