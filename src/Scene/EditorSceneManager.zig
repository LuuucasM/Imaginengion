const std = @import("std");
const ECSManager = @import("../ECS/ECSManager.zig");
const ESceneState = @import("../ECS/")
const FrameBufferFile = @import("../FrameBuffers/FrameBuffer.zig");
const FrameBuffer = FrameBufferFile.FrameBuffer;
const TextureFormat = FrameBufferFile.TextureFormat;
const SceneLayer = @import("SceneLayer.zig");
const EditorSceneManager = @This();

const ESceneState = enum {
    Stop,
    Play,
}

mFrameBuffer: FrameBuffer(&.{TextureFormat.RGBA8, TextureFormat.RED_INTEGER}, TextureFormat.DEPTH24STENCIL8, 1, false),
mActiveScene: ?SceneLayer,
mSceneState: ESceneState,
mECSManager: ECSManager,

pub fn Init(width: usize, height: usize) EditorSceneManager {
    return EditorSceneManager{
        .mFrameBuffer = FrameBuffer(&.{TextureFormat.RGBA8, TextureFormat.RED_INTEGER}, TextureFormat.DEPTH24STENCIL8, 1, false).Init(width, height),
        .mActiveScene = null,
        .mSceneState = ESceneState.Stop,
        .mECSManager = ECSManager.Init();
    };
}

pub fn Deinit(self: *SceneManager) void {
    self.mFrameBuffer.Deinit();
    if (self.mActiveScene) |scene_layer|{
        scene_layer.Deinit();
    }
    self.mECSManager.Deinit();
}

pub fn CreateEntity(self: SceneManager, name: [24]u8) !?Entity {
    if (self.mActiveScene) |scene_layer|{
        return self.CreateEntityWithUUID(name, try GenUUID());
    }
    return null;
}
pub fn CreateEntityWithUUID(self: SceneManager, name: [24]u8, uuid: u64) !?Entity {
    if (self.mActiveScene) |scene_layer|{
        const e = Entity{ .mEntityID = try self.mECSManager.CreateEntity(), .mLayerType = self.mActiveScene.?.mLayerType, .mECSManager = &self.mECSManager };
        _ = e.AddComponent(IDComponent, .{ .ID = uuid });
        _ = e.AddComponent(SceneIDComponent, .{ .ID = self.mActiveScene.?.mUUID, .LayerType = self.mActiveScene.?. });
        _ = e.AddComponent(NameComponent, .{ .Name = name });
        _ = e.AddComponent(TransformComponent, .{ .Transform = LinAlg.InitMat4CompTime(1.0) });
        return e;
    }
    return null;
}

pub fn DestroyEntity(self: SceneLayerEditor, e: Entity) !void {
    if (self.mActiveScene) |scene_layer|{
        try self.mECSManager.DestroyEntity(e.mEntityID);
    }
}
pub fn DuplicateEntity(self: SceneLayerEditor, original_entity: Entity) ?Entity {
    if (self.mActiveScene) |scene_layer|{
        return Entity{ .mEntityID = try self.mECSManager.DuplicateEntity(original_entity.mEntityID), .mLayerType = self.mLayerType, .mLayer = self };
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