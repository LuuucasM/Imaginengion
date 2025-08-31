pub const IDComponent = @import("Components/IDComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const SceneComponent = @import("Components/SceneComponent.zig");
pub const ScriptComponent = @import("Components/ScriptComponent.zig");
pub const StackPosComponent = @import("Components/StackPosComponent.zig");
pub const TransformComponent = @import("Components/TransformComponent.zig");

const TagComponents = @import("Components/TagComponents.zig");
pub const OnSceneStartScript = TagComponents.OnSceneStartScript;

pub const ComponentsList = [_]type{
    IDComponent,
    NameComponent,
    SceneComponent,
    ScriptComponent,
    StackPosComponent,
    TransformComponent,
    OnSceneStartScript,
};

pub const EComponents = enum(u16) {
    IDComponent = IDComponent.Ind,
    NameComponent = NameComponent.Ind,
    SceneComponent = SceneComponent.Ind,
    ScriptComponent = ScriptComponent.Ind,
    StackPosComponent = StackPosComponent.Ind,
    TransformComponent = TransformComponent.Ind,
    OnSceneStartScript = OnSceneStartScript.Ind,
};
