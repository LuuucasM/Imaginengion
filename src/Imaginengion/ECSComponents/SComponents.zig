const ListInd = @import("../ECS/Components.zig").ListInd;
const std = @import("std");
pub const UUIDComponent = @import("Shared/UUIDComponent.zig");
pub const NameComponent = @import("Shared/NameComponent.zig");
pub const PhysicsComponent = @import("Scene/PhysicsComponent.zig");
pub const SceneComponent = @import("Scene/SceneComponent.zig");
pub const ScriptComponent = @import("Shared/ScriptComponent.zig");
pub const SpawnPossComponent = @import("Scene/SpawnPossComponent.zig");
pub const StackPosComponent = @import("Scene/StackPosComponent.zig");
pub const TmplRefComponent = @import("Shared/TmplRefComponent.zig");
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
    TmplRefComponent,

    //Scripts
    ScriptComponent,
    OnSceneStartScript,
    OnUpdateScript,
    InputPressedScript,
};

pub const ComponentsPanelList = [_]type{
    UUIDComponent,
    NameComponent,
    SceneComponent,
    PhysicsComponent,
    SpawnPossComponent,
    TmplRefComponent,
};

/// ScriptComponent is not listed, scripts are saved separately and recreated with AddScript
pub const SerializeList = [_]type{
    UUIDComponent,
    NameComponent,
    PhysicsComponent,
    SceneComponent,
    SpawnPossComponent,
    TmplRefComponent,
};

/// What a linked copy keeps of its own when it is stripped down (see ECSObject.Core.Strip), everything
/// else in SerializeList it gets from its template
pub const ShellList = [_]type{
    UUIDComponent,
    NameComponent,
    //its layer is what gives it its slot in the scene stack
    SceneComponent,
    TmplRefComponent,
};

pub const ScriptsList = [_]type{
    OnSceneStartScript,
    OnUpdateScript,
    InputPressedScript,
};

pub const EComponents = enum(u16) {
    UUIDComponent = ListInd(&ComponentsList, UUIDComponent),
    NameComponent = ListInd(&ComponentsList, NameComponent),
    PhysicsComponent = ListInd(&ComponentsList, PhysicsComponent),
    SceneComponent = ListInd(&ComponentsList, SceneComponent),
    ScriptComponent = ListInd(&ComponentsList, ScriptComponent),
    SpawnPossComponent = ListInd(&ComponentsList, SpawnPossComponent),
    StackPosComponent = ListInd(&ComponentsList, StackPosComponent),
    TmplRefComponent = ListInd(&ComponentsList, TmplRefComponent),

    OnSceneStartScript = ListInd(&ComponentsList, OnSceneStartScript),
    OnUpdateScript = ListInd(&ComponentsList, OnUpdateScript),
    InputPressedScript = ListInd(&ComponentsList, InputPressedScript),
};
