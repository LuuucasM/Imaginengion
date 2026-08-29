const std = @import("std");
pub const UUIDComponent = @import("Shared/UUIDComponent.zig");
pub const NameComponent = @import("Shared/NameComponent.zig");
pub const PhysicsComponent = @import("Scene/PhysicsComponent.zig");
pub const SceneComponent = @import("Scene/SceneComponent.zig");
pub const ScriptComponent = @import("Shared/ScriptComponent.zig");
pub const SpawnPossComponent = @import("Scene/SpawnPossComponent.zig");
pub const StackPosComponent = @import("Scene/StackPosComponent.zig");
//pub const TransformComponent = @import("Components/TransformComponent.zig");

const ScriptTags = @import("Shared/ScriptTags.zig");
pub const OnSceneStartScript = ScriptTags.OnSceneStartScript;
pub const OnUpdateScript = ScriptTags.SceneOnUpdateScript;
pub const InputPressedScript = ScriptTags.InputPressedScript;

pub const ComponentsList = [_]type{
    //SceneLayer
    UUIDComponent,
    NameComponent,
    PhysicsComponent,
    SceneComponent,
    SpawnPossComponent,
    StackPosComponent,

    //Scripts
    ScriptComponent,
    OnSceneStartScript,
    OnUpdateScript,
    InputPressedScript,
};

pub const ComponentsPanelList = [_]type{
    UUIDComponent,
    NameComponent,
    PhysicsComponent,
    SpawnPossComponent,
};

pub const SerializeList = [_]type{
    UUIDComponent,
    NameComponent,
    PhysicsComponent,
    SceneComponent,
    SpawnPossComponent,
    ScriptComponent,
};

pub const ScriptsList = [_]type{
    OnSceneStartScript,
    OnUpdateScript,
    InputPressedScript,
};

pub const EComponents = enum(u16) {
    UUIDComponent = UUIDComponent.Ind,
    NameComponent = NameComponent.Ind,
    PhysicsComponent = PhysicsComponent.Ind,
    SceneComponent = SceneComponent.Ind,
    ScriptComponent = ScriptComponent.Ind,
    SpawnPossComponent = SpawnPossComponent.Ind,
    StackPosComponent = StackPosComponent.Ind,

    OnSceneStartScript = OnSceneStartScript.Ind,
    OnUpdateScript = OnUpdateScript.Ind,
    InputPressedScript = InputPressedScript.Ind,
};
