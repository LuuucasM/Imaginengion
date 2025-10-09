const std = @import("std");
pub const AISlotComponent = @import("Components/AISlotComponent.zig");
pub const CameraComponent = @import("Components/CameraComponent.zig");
pub const IDComponent = @import("Components/IDComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const PlayerSlotComponent = @import("Components/PlayerSlotComponent.zig");
pub const QuadComponent = @import("Components/QuadComponent.zig");
pub const SceneIDComponent = @import("Components/SceneIDComponent.zig");
pub const TransformComponent = @import("Components/TransformComponent.zig");
pub const ScriptComponent = @import("Components/ScriptComponent.zig");
pub const TextComponent = @import("Components/TextComponent.zig");

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
    TextComponent,
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
    TextComponent = TextComponent.Ind,
    TransformComponent = TransformComponent.Ind,
    ScriptComponent = ScriptComponent.Ind,
    OnInputPressedScript = OnInputPressedScript.Ind,
    OnUpdateInputScript = OnUpdateInputScript.Ind,
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
