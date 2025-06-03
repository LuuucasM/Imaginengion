const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const Entity = @import("../../GameObjects/Entity.zig");
const ECSManagerScenes = @import("../SceneManager.zig").ECSManagerScenes;
const FrameBuffer = @import("../../FrameBuffers/FrameBuffer.zig");
const GenUUID = @import("../../Core/UUID.zig").GenUUID;
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const AssetManager = @import("../../Assets/AssetManager.zig");

const GameComponents = @import("../../GameObjects/Components.zig");
const IDComponent = GameComponents.IDComponent;
const SceneIDComponent = GameComponents.SceneIDComponent;
const NameComponent = GameComponents.NameComponent;
const TransformComponent = GameComponents.TransformComponent;
const CameraComponent = GameComponents.CameraComponent;

const SceneComponent = @This();

pub const LayerType = enum(u1) {
    GameLayer = 0,
    OverlayLayer = 1,
};

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == SceneComponent) {
            break :blk i;
        }
    }
};

mSceneAssetHandle: AssetHandle = .{ .mID = AssetHandle.NullHandle },
mLayerType: LayerType = undefined,
mFrameBuffer: FrameBuffer = undefined,

pub fn Deinit(self: *SceneComponent) !void {
    self.mFrameBuffer.Deinit();
    if (self.mSceneAssetHandle.mID != AssetHandle.NullHandle) {
        AssetManager.ReleaseAssetHandleRef(&self.mSceneAssetHandle);
    }
}

pub fn GetInd(self: SceneComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn GetName(self: SceneComponent) []const u8 {
    _ = self;
    return "SceneComponent";
}
