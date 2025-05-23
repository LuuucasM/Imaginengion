const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const EntityType = @import("../SceneManager.zig").EntityType;
const Entity = @import("../../GameObjects/Entity.zig");
const ECSManagerScenes = @import("../SceneManager.zig").ECSManagerScenes;
const FrameBuffer = @import("../../FrameBuffers/FrameBuffer.zig");
const GenUUID = @import("../../Core/UUID.zig").GenUUID;
const AssetHandle = @import("../../Assets/AssetHandle.zig");

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

pub fn Deinit(_: *SceneComponent) !void {}

pub fn GetInd(self: SceneComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn GetName(self: SceneComponent) []const u8 {
    _ = self;
    return "SceneComponent";
}
