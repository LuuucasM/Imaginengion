const std = @import("std");
pub const AISlotComponent = @import("Components/AISlotComponent.zig");
pub const AudioComponent = @import("Components/AudioComponent.zig");
pub const CameraComponent = @import("Components/CameraComponent.zig");
pub const ColliderComponent = @import("Components/ColliderComponent.zig");
pub const IDComponent = @import("Components/IDComponent.zig");
pub const MicComponent = @import("Components/MicComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const PlayerSlotComponent = @import("Components/PlayerSlotComponent.zig");
pub const QuadComponent = @import("Components/QuadComponent.zig");
pub const RigidBodyComponent = @import("Components/RigidBodyComponent.zig");
pub const SceneIDComponent = @import("Components/SceneIDComponent.zig");
pub const TransformComponent = @import("Components/TransformComponent.zig");
pub const ScriptComponent = @import("Components/ScriptComponent.zig");
pub const TextComponent = @import("Components/TextComponent.zig");

const TagComponents = @import("Components/TagComponents.zig");
pub const OnInputPressedScript = TagComponents.OnInputPressedScript;
pub const OnUpdateScript = TagComponents.OnUpdateScript;

pub const ComponentsList = [_]type{
    AISlotComponent,
    AudioComponent,
    CameraComponent,
    ColliderComponent,
    IDComponent,
    MicComponent,
    NameComponent,
    PlayerSlotComponent,
    QuadComponent,
    RigidBodyComponent,
    SceneIDComponent,
    TextComponent,
    TransformComponent,
    ScriptComponent,
    OnInputPressedScript,
    OnUpdateScript,
};

pub const ScriptList = [_]type{
    OnInputPressedScript,
    OnUpdateScript,
};

pub const EComponents = enum(u16) {
    AISlotComponent = AISlotComponent.Ind,
    AudioComponent = AudioComponent.Ind,
    CameraComponent = CameraComponent.Ind,
    ColliderComponent = ColliderComponent.Ind,
    IDComponent = IDComponent.Ind,
    MicComponent = MicComponent.Ind,
    NameComponent = NameComponent.Ind,
    PlayerSlotComponent = PlayerSlotComponent.Ind,
    QuadComponent = QuadComponent.Ind,
    RigidBodyComponent = RigidBodyComponent.Ind,
    SceneIDComponent = SceneIDComponent.Ind,
    TextComponent = TextComponent.Ind,
    TransformComponent = TransformComponent.Ind,
    ScriptComponent = ScriptComponent.Ind,
    OnInputPressedScript = OnInputPressedScript.Ind,
    OnUpdateScript = OnUpdateScript.Ind,
};
