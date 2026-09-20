const std = @import("std");
const EntitySceneComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const SceneLayer = @import("../../ECSObjects/Scene.zig");

pub const Editable: bool = false;
pub const Name: []const u8 = "EntitySceneComponent";

mScene: SceneLayer = undefined,

pub fn Deinit(_: *EntitySceneComponent, _: *EngineContext) void {}
