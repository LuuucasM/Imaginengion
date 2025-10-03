pub const AISlotComponent = @import("Components/AISlotComponent.zig");
pub const CameraComponent = @import("Components/CameraComponent.zig");
pub const IDComponent = @import("Components/IDComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const PlayerSlotComponent = @import("Components/PlayerSlotComponent.zig");
pub const QuadComponent = @import("Components/QuadComponent.zig");
pub const SceneIDComponent = @import("Components/SceneIDComponent.zig");
pub const TransformComponent = @import("Components/TransformComponent.zig");
pub const ScriptComponent = @import("Components/ScriptComponent.zig");

const TagComponents = @import("Components/TagComponents.zig");
pub const OnInputPressedScript = TagComponents.OnInputPressedScript;
pub const OnUpdateInputScript = TagComponents.OnUpdateInputScript;

pub const ComponentsList = [_]type{
    AISlotComponent,
    CameraComponent,
    IDComponent,
    NameComponent,
    PlayerSlotComponent,
    QuadComponent,
    SceneIDComponent,
    TransformComponent,
    ScriptComponent,
    OnInputPressedScript,
    OnUpdateInputScript,
};

pub const EComponents = enum(u16) {
    AISlotComponent = AISlotComponent.Ind,
    CameraComponent = CameraComponent.Ind,
    IDComponent = IDComponent.Ind,
    NameComponent = NameComponent.Ind,
    PlayerSlotComponent = PlayerSlotComponent.Ind,
    QuadComponent = QuadComponent.Ind,
    SceneIDComponent = SceneIDComponent.Ind,
    TransformComponent = TransformComponent.Ind,
    ScriptComponent = ScriptComponent.Ind,
    OnInputPressedScript = OnInputPressedScript.Ind,
    OnUpdateInputScript = OnUpdateInputScript.Ind,
};
