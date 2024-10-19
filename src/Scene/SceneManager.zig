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
const SceneManager = @This();

const Components = @import("../ECS/Components.zig");
const IDComponent = Components.IDComponent;
const SceneIDComponent = Components.SceneIDComponent;
const NameComponent = Components.NameComponent;
const TransformComponent = Components.TransformComponent;

const SerializeSceneText = @import("SceneSerializer.zig").SerializeText;
const DeserializeSceneText = @import("SceneSerializer.zig").DeserializeText;

pub const ESceneState = enum {
    Stop,
    Play,
};

var SceneManagerGPA: std.heap.GeneralPurposeAllocator(.{}) = .{};

mFrameBuffer: FrameBuffer(&[_]TextureFormat{ .RGBA8, .RED_INTEGER }, .DEPTH24STENCIL8, 1, false),
mSceneStack: std.ArrayList(SceneLayer),
mECSManager: ECSManager,
mSceneState: ESceneState,

pub fn Init(width: usize, height: usize) !SceneManager {
    return SceneManager{
        .mFrameBuffer = FrameBuffer(&[_]TextureFormat{ .RGBA8, .RED_INTEGER }, .DEPTH24STENCIL8, 1, false).Init(width, height),
        .mSceneStack = std.ArrayList(SceneLayer).init(SceneManagerGPA.allocator()),
        .mECSManager = try ECSManager.Init(SceneManagerGPA.allocator()),
        .mSceneState = .Stop,
    };
}

pub fn Deinit(self: *SceneManager) !void {
    var iter = std.mem.reverseIterator(self.mSceneStack.items);
    while (iter.next()) |scene_layer| {
        try self.RemoveScene(scene_layer.mUUID);
    }
    self.mSceneStack.deinit();
    self.mFrameBuffer.Deinit();
    self.mECSManager.Deinit();
    _ = SceneManagerGPA.deinit();
}

pub fn CreateEntity(self: SceneManager, name: [24]u8, scene_id: u128) !?Entity {
    for (self.mSceneStack.items) |scene_layer| {
        if (scene_layer.mUUID == scene_id) {
            return self.CreateEntityWithUUID(name, GenUUID(), scene_id);
        }
    }
    return null;
}
pub fn CreateEntityWithUUID(self: SceneManager, name: [24]u8, uuid: u128, scene_id: u128) !?Entity {
    for (self.mSceneStack.items) |scene_layer| {
        if (scene_layer.mUUID == scene_id) {
            const e = Entity{ .mEntityID = try self.mECSManager.CreateEntity(), .mLayerType = scene_layer.mLayerType, .mECSManager = &self.mECSManager };
            _ = e.AddComponent(IDComponent, .{ .ID = uuid });
            _ = e.AddComponent(SceneIDComponent, .{ .ID = scene_layer.mUUID, .LayerType = scene_layer.mLayerType });
            _ = e.AddComponent(NameComponent, .{ .Name = name });
            _ = e.AddComponent(TransformComponent, .{ .Transform = LinAlg.InitMat4CompTime(1.0) });

            scene_layer.mEntities.add(e.mEntityID);

            return e;
        }
    }
    return null;
}

pub fn DestroyEntity(self: SceneManager, e: Entity, scene_id: u128) !void {
    for (self.mSceneStack.items) |scene_layer| {
        if (scene_layer.mUUID == scene_id) {
            try self.mECSManager.DestroyEntity(e.mEntityID);
            scene_layer.mEntities.remove(e.mEntityID);
        }
    }
}
pub fn DuplicateEntity(self: SceneManager, original_entity: Entity, scene_id: u128) !?Entity {
    for (self.mSceneStack.items) |scene_layer| {
        if (scene_layer.mUUID == scene_id) {
            const new_entity = Entity{ .mEntityID = try self.mECSManager.DuplicateEntity(original_entity.mEntityID), .mLayerType = scene_layer.mLayerType, .mLayer = scene_layer };
            scene_layer.mEntities.add(new_entity.mEntityID);
            return new_entity;
        }
    }
    return null;
}

//pub fn OnRuntimeStart() void {}
//pub fn OnRuntimeStop() void{}
//pub fn OnUpdateRuntime() void {}
//pub fn OnUpdateEditor() void {}
//pub fn OnEvent() void {}
//pub fn SetSceneName() void {}
//fn OnViewportResize void {}
pub fn NewScene(self: *SceneManager, layer_type: LayerType) !void {
    try self.mSceneStack.append(try SceneLayer.Init(SceneManagerGPA.allocator(), layer_type));
}
pub fn RemoveScene(self: *SceneManager, scene_id: u128) !void {
    var iter = std.mem.reverseIterator(self.mSceneStack.items);
    var i: usize = self.mSceneStack.items.len - 1;
    while (iter.nextPtr()) |scene_layer| {
        if (scene_layer.mUUID == scene_id) {
            if (scene_layer.mPath != null) {
                try self.SaveScene(scene_id);
            } else {
                try self.SaveAsScene(scene_id);
            }
            if (scene_layer.mPath != null) {
                SceneManagerGPA.allocator().free(scene_layer.mPath.?);
            }
            SceneManagerGPA.allocator().free(scene_layer.mName.?);
            scene_layer.Deinit();
            _ = self.mSceneStack.orderedRemove(i);
            return;
        }
        i -= 1;
    }
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
pub fn SaveScene(self: *SceneManager, scene_id: u128) !void {
    for (self.mSceneStack.items) |scene_layer| {
        if (scene_layer.mUUID == scene_id) {
            if (scene_layer.mPath == null) {
                self.SaveAsScene(scene_id);
            } else {
                try SceneSerializer.SerializeText(scene_layer, self);
            }
            return;
        }
    }
}
pub fn SaveAsScene(self: *SceneManager, scene_id: u128) !void {
    for (self.mSceneStack.items) |*scene_layer| {
        if (scene_layer.mUUID == scene_id) {
            var buffer: [260]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buffer);

            const path = try PlatformUtils.SaveFile(fba.allocator(), "imsc");
            if (path.len > 0) {
                const scene_basename = std.fs.path.basename(path);
                const dot_location = std.mem.indexOf(u8, scene_basename, ".") orelse 0;
                const scene_name = scene_basename[0..dot_location];
                scene_layer.mName = try SceneManagerGPA.allocator().dupe(u8, scene_name);
                scene_layer.mPath = try SceneManagerGPA.allocator().dupe(u8, path);
                try SceneSerializer.SerializeText(scene_layer.*, self);
            }
            return;
        }
    }
}
