const std = @import("std");
pub const UUIDComponent = @import("Components/UUIDComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const PhysicsComponent = @import("Components/PhysicsComponent.zig");
pub const SceneComponent = @import("Components/SceneComponent.zig");
pub const ScriptComponent = @import("Components/ScriptComponent.zig");
pub const SpawnPossComponent = @import("Components/SpawnPossComponent.zig");
pub const StackPosComponent = @import("Components/StackPosComponent.zig");
//pub const TransformComponent = @import("Components/TransformComponent.zig");

const TagComponents = @import("Components/TagComponents.zig");
pub const OnSceneStartScript = TagComponents.OnSceneStartScript;
pub const OnUpdateScript = TagComponents.OnUpdateScript;
pub const InputPressedScript = TagComponents.InputPressedScript;

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

pub const PanelList = [_]type{
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
    StackPosComponent,
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
