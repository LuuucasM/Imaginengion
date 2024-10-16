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
const EditorSceneManager = @This();

const Components = @import("../ECS/Components.zig");
const IDComponent = Components.IDComponent;
const SceneIDComponent = Components.SceneIDComponent;
const NameComponent = Components.NameComponent;
const TransformComponent = Components.TransformComponent;

pub const ESceneState = enum {
    Stop,
    Play,
};

var ECSGPA: std.heap.GeneralPurposeAllocator(.{}) = .{};

mFrameBuffer: FrameBuffer(&[_]TextureFormat{ .RGBA8, .RED_INTEGER }, .DEPTH24STENCIL8, 1, false),
mActiveScene: ?SceneLayer,
mSceneState: ESceneState,
mECSManager: ECSManager,

pub fn Init(width: usize, height: usize) !EditorSceneManager {
    return EditorSceneManager{
        .mFrameBuffer = FrameBuffer(&[_]TextureFormat{ .RGBA8, .RED_INTEGER }, .DEPTH24STENCIL8, 1, false).Init(width, height),
        .mActiveScene = null,
        .mSceneState = .Stop,
        .mECSManager = try ECSManager.Init(ECSGPA.allocator()),
    };
}

pub fn Deinit(self: *EditorSceneManager) void {
    self.mFrameBuffer.Deinit();
    if (self.mActiveScene) |*scene_layer| {
        scene_layer.Deinit();
    }
    self.mECSManager.Deinit();
    _ = ECSGPA.deinit();
}

pub fn CreateEntity(self: EditorSceneManager, name: [24]u8) !?Entity {
    if (self.mActiveScene) {
        return self.CreateEntityWithUUID(name, try GenUUID());
    }
    return null;
}
pub fn CreateEntityWithUUID(self: EditorSceneManager, name: [24]u8, uuid: u64) !?Entity {
    if (self.mActiveScene) |scene_layer| {
        const e = Entity{ .mEntityID = try self.mECSManager.CreateEntity(), .mLayerType = scene_layer.mLayerType, .mECSManager = &self.mECSManager };
        _ = e.AddComponent(IDComponent, .{ .ID = uuid });
        _ = e.AddComponent(SceneIDComponent, .{ .ID = self.mActiveScene.?.mUUID, .LayerType = scene_layer.mLayerType });
        _ = e.AddComponent(NameComponent, .{ .Name = name });
        _ = e.AddComponent(TransformComponent, .{ .Transform = LinAlg.InitMat4CompTime(1.0) });

        scene_layer.mEntities.add(e.mEntityID);

        return e;
    }
    return null;
}

pub fn DestroyEntity(self: EditorSceneManager, e: Entity) !void {
    if (self.mActiveScene) |scene_layer| {
        try self.mECSManager.DestroyEntity(e.mEntityID);
        scene_layer.mEntities.remove(e.mEntityID);
    }
}
pub fn DuplicateEntity(self: EditorSceneManager, original_entity: Entity) !?Entity {
    if (self.mActiveScene) |scene_layer| {
        const new_entity = Entity{ .mEntityID = try self.mECSManager.DuplicateEntity(original_entity.mEntityID), .mLayerType = self.mLayerType, .mLayer = self };
        scene_layer.mEntities.add(new_entity.mEntityID);
        return new_entity;
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
pub fn NewScene(self: EditorSceneManager, layer_type: LayerType) void {
    if (self.mActiveScene) |scene_layer| {
        self.SaveScene();
        if (std.mem.eql(u8, scene_layer.mName, std.mem.zeroes([24]u8)) == true) {
            self.SaveAsScene();
        } else {
            self.SaveScene();
        }
        scene_layer.Deinit();
    }
    self.mActiveScene = SceneLayer.Init(ECSGPA.allocator(), layer_type);
}
pub fn LoadScene() void{}
pub fn SaveScene() void {}
pub fn SaveAsScene() void {}
