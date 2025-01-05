const std = @import("std");
const LinAlg = @import("../Math/LinAlg.zig");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const ECSManager = @import("../ECS/ECSManager.zig");
const Entity = @import("../ECS/Entity.zig");
const FrameBufferFile = @import("../FrameBuffers/FrameBuffer.zig");
const FrameBuffer = FrameBufferFile.FrameBuffer;
const TextureFormat = FrameBufferFile.TextureFormat;
const SceneLayer = @import("SceneLayer.zig");
const LayerType = SceneLayer.LayerType;
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const SceneSerializer = @import("SceneSerializer.zig");
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const ComponentsArray = @import("../ECS/Components.zig").ComponentsList;
const SceneManager = @This();

pub const ESceneState = enum {
    Stop,
    Play,
};

var SceneManagerGPA: std.heap.GeneralPurposeAllocator(.{}) = .{};

mFrameBuffer: FrameBuffer(&[_]TextureFormat{ .RGBA8, .RED_INTEGER }, .DEPTH24STENCIL8, 1, false),
mSceneStack: std.ArrayList(SceneLayer),
mECSManager: ECSManager,
mSceneState: ESceneState,
mLayerInsertIndex: usize,

pub fn Init(width: usize, height: usize) !SceneManager {
    return SceneManager{
        .mFrameBuffer = FrameBuffer(&[_]TextureFormat{ .RGBA8, .RED_INTEGER }, .DEPTH24STENCIL8, 1, false).Init(width, height),
        .mSceneStack = std.ArrayList(SceneLayer).init(SceneManagerGPA.allocator()),
        .mECSManager = try ECSManager.Init(SceneManagerGPA.allocator(), &ComponentsArray),
        .mSceneState = .Stop,
        .mLayerInsertIndex = 0,
    };
}

pub fn Deinit(self: *SceneManager) !void {
    var iter = std.mem.reverseIterator(self.mSceneStack.items);
    while (iter.next()) |scene_layer| {
        try self.RemoveScene(scene_layer.mInternalID);
    }
    self.mSceneStack.deinit();
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
//pub fn OnUpdateEditor() void {}
//pub fn OnEvent() void {}
//pub fn SetSceneName() void {}
//fn OnViewportResize void {}

pub fn NewScene(self: *SceneManager, layer_type: LayerType) !usize {
    var new_scene = try SceneLayer.Init(SceneManagerGPA.allocator(), layer_type, 9999, &self.mECSManager);
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
    var new_scene = try SceneLayer.Init(SceneManagerGPA.allocator(), .GameLayer, self.mSceneStack.items.len, &self.mECSManager);

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
