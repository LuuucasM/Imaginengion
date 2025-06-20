pub const IDComponent = @import("Components/IDComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const SceneComponent = @import("Components/SceneComponent.zig");
pub const ScriptComponent = @import("Components/ScriptComponent.zig");
pub const StackPosComponent = @import("Components/StackPosComponent.zig");

const TagComponents = @import("Components/TagComponents.zig");
pub const OnSceneStartScript = TagComponents.OnSceneStartScript;

pub const ComponentsList = [_]type{
    IDComponent,
    NameComponent,
    SceneComponent,
    ScriptComponent,
    StackPosComponent,
    OnSceneStartScript,
};
