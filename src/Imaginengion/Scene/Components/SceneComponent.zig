const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const Entity = @import("../../GameObjects/Entity.zig");
const ECSManagerScenes = @import("../SceneManager.zig").ECSManagerScenes;
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

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
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;

mSceneAssetHandle: AssetHandle = .{},
mLayerType: LayerType = undefined,

pub fn Deinit(self: *SceneComponent) !void {
    self.mSceneAssetHandle.ReleaseAsset();
}

pub fn GetInd(self: SceneComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn GetName(self: SceneComponent) []const u8 {
    _ = self;
    return "SceneComponent";
}
