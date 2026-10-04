const ListInd = @import("../ECS/Components.zig").ListInd;
const std = @import("std");
pub const AttribComponent = @import("Shared/AttribComponent.zig");
pub const UUIDComponent = @import("Shared/UUIDComponent.zig");
pub const NameComponent = @import("Shared/NameComponent.zig");
pub const PhysicsComponent = @import("Scene/PhysicsComponent.zig");
pub const SceneComponent = @import("Scene/SceneComponent.zig");
pub const ScriptComponent = @import("Shared/ScriptComponent.zig");
pub const SpawnPossComponent = @import("Scene/SpawnPossComponent.zig");
pub const StackPosComponent = @import("Scene/StackPosComponent.zig");
pub const TmplRefComponent = @import("Shared/TmplRefComponent.zig");
pub const GameLayerTag = @import("Shared/TagComponents.zig").GameLayerTag;
pub const OverlayLayerTag = @import("Shared/TagComponents.zig").OverlayLayerTag;
//pub const TransformComponent = @import("Components/TransformComponent.zig");

const ScriptTags = @import("Shared/ScriptTags.zig");
pub const OnSceneStartScript = ScriptTags.OnSceneStartScript;
pub const OnUpdateScript = ScriptTags.SceneOnUpdateScript;
pub const InputPressedScript = ScriptTags.InputPressedScript;
pub const OnPhysicsUpdateScript = ScriptTags.SceneOnPhysicsUpdateScript;

pub const ComponentsList = [_]type{
    //SceneLayer
    AttribComponent,
    UUIDComponent,
    NameComponent,
    PhysicsComponent,
    SceneComponent,
    SpawnPossComponent,
    StackPosComponent,
    TmplRefComponent,
    GameLayerTag,
    OverlayLayerTag,

    //Scripts
    ScriptComponent,
    OnSceneStartScript,
    OnUpdateScript,
    InputPressedScript,
    OnPhysicsUpdateScript,
};

pub const ComponentsPanelList = [_]type{
    UUIDComponent,
    NameComponent,
    AttribComponent,
    SceneComponent,
    PhysicsComponent,
    SpawnPossComponent,
    TmplRefComponent,
};

/// ScriptComponent is not listed, scripts are saved separately and recreated with AddScript
pub const SerializeList = [_]type{
    UUIDComponent,
    NameComponent,
    AttribComponent,
    PhysicsComponent,
    SceneComponent,
    SpawnPossComponent,
    TmplRefComponent,
    //a scene's layer is saved as its tag, and reading it back is what slots the scene into the stack
    GameLayerTag,
    OverlayLayerTag,
};

/// What a linked copy keeps of its own when it is stripped down (see ECSObject.Core.Strip), everything
/// else in SerializeList it gets from its template
pub const ShellList = [_]type{
    UUIDComponent,
    NameComponent,
    SceneComponent,
    TmplRefComponent,
    //its layer is what gives it its slot in the scene stack
    GameLayerTag,
    OverlayLayerTag,
};

pub const ScriptsList = [_]type{
    OnSceneStartScript,
    OnUpdateScript,
    InputPressedScript,
    OnPhysicsUpdateScript,
};

pub const EComponents = enum(u16) {
    AttribComponent = ListInd(&ComponentsList, AttribComponent),
    UUIDComponent = ListInd(&ComponentsList, UUIDComponent),
    NameComponent = ListInd(&ComponentsList, NameComponent),
    PhysicsComponent = ListInd(&ComponentsList, PhysicsComponent),
    SceneComponent = ListInd(&ComponentsList, SceneComponent),
    ScriptComponent = ListInd(&ComponentsList, ScriptComponent),
    SpawnPossComponent = ListInd(&ComponentsList, SpawnPossComponent),
    StackPosComponent = ListInd(&ComponentsList, StackPosComponent),
    TmplRefComponent = ListInd(&ComponentsList, TmplRefComponent),
    GameLayerTag = ListInd(&ComponentsList, GameLayerTag),
    OverlayLayerTag = ListInd(&ComponentsList, OverlayLayerTag),

    OnSceneStartScript = ListInd(&ComponentsList, OnSceneStartScript),
    OnUpdateScript = ListInd(&ComponentsList, OnUpdateScript),
    InputPressedScript = ListInd(&ComponentsList, InputPressedScript),
    OnPhysicsUpdateScript = ListInd(&ComponentsList, OnPhysicsUpdateScript),
};
