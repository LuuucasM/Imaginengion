const std = @import("std");
const SceneAsset = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const Scene = @import("../../ECSObjects/Scene.zig");

pub const empty: SceneAsset = .{
    .mScene = .empty,
};

mScene: Scene,

pub fn Deinit(_: *SceneAsset, _: *EngineContext) void {}

pub const Name: []const u8 = "SceneAsset";
