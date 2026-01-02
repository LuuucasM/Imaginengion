const std = @import("std");
pub const AISlotComponent = @import("Components/AISlotComponent.zig");
pub const AudioComponent = @import("Components/AudioComponent.zig");
pub const CameraComponent = @import("Components/CameraComponent.zig");
pub const IDComponent = @import("Components/IDComponent.zig");
pub const MicComponent = @import("Components/MicComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const PlayerSlotComponent = @import("Components/PlayerSlotComponent.zig");
pub const QuadComponent = @import("Components/QuadComponent.zig");
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
    IDComponent,
    MicComponent,
    NameComponent,
    PlayerSlotComponent,
    QuadComponent,
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
    IDComponent = IDComponent.Ind,
    MicComponent = MicComponent.Ind,
    NameComponent = NameComponent.Ind,
    PlayerSlotComponent = PlayerSlotComponent.Ind,
    QuadComponent = QuadComponent.Ind,
    SceneIDComponent = SceneIDComponent.Ind,
    TextComponent = TextComponent.Ind,
    TransformComponent = TransformComponent.Ind,
    ScriptComponent = ScriptComponent.Ind,
    OnInputPressedScript = OnInputPressedScript.Ind,
    OnUpdateScript = OnUpdateScript.Ind,
};

comptime {
    for (ComponentsList) |component_type| {
        const type_name = std.fmt.comptimePrint(" {s}\n", .{@typeName(component_type)});
        if (@hasDecl(component_type, "Editable") == true) {
            const is_editable = component_type.Editable;
            if (is_editable) {
                if (std.meta.hasFn(component_type, "EditorRender") == false) {
                    @compileError("Component type is editable but does not have a EditorRender function" ++ type_name);
                }
            }
        } else {
            @compileError("Component type does not contain an editable field" ++ type_name);
        }
        if (std.meta.hasFn(component_type, "GetName") == false) {
            @compileError("Component type does not contain a GetName function" ++ type_name);
        }
        if (std.meta.hasFn(component_type, "GetInd") == false) {
            @compileError("Component type does not contain a GetInd function" ++ type_name);
        }
    }
}
