const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");

pub const AISlotComponent = @import("Components/AISlotComponent.zig");
pub const AudioComponent = @import("Components/AudioComponent.zig");
pub const CameraComponent = @import("Components/CameraComponent.zig");
pub const ColliderComponent = @import("Components/ColliderComponent.zig");
pub const UUIDComponent = @import("Components/UUIDComponent.zig");
pub const MicComponent = @import("Components/MicComponent.zig");
pub const NameComponent = @import("Components/NameComponent.zig");
pub const PlayerSlotComponent = @import("Components/PlayerSlotComponent.zig");
pub const QuadComponent = @import("Components/QuadComponent.zig");
pub const RigidBodyComponent = @import("Components/RigidBodyComponent.zig");
pub const EntitySceneComponent = @import("Components/EntitySceneComponent.zig");
pub const TransformComponent = @import("Components/TransformComponent.zig");
pub const ScriptComponent = @import("Components/ScriptComponent.zig");
pub const TextComponent = @import("Components/TextComponent.zig");

const TagComponents = @import("Components/TagComponents.zig");
pub const OnInputPressedScript = TagComponents.OnInputPressedScript;
pub const OnUpdateScript = TagComponents.OnUpdateScript;

pub const ComponentsList = [_]type{
    //components
    AISlotComponent,
    AudioComponent,
    CameraComponent,
    ColliderComponent,
    UUIDComponent,
    MicComponent,
    NameComponent,
    PlayerSlotComponent,
    QuadComponent,
    RigidBodyComponent,
    EntitySceneComponent,
    TextComponent,
    TransformComponent,

    //scripts
    ScriptComponent,
    OnInputPressedScript,
    OnUpdateScript,
};

pub const SerializeList = [_]type{
    AISlotComponent,
    AudioComponent,
    CameraComponent,
    ColliderComponent,
    UUIDComponent,
    MicComponent,
    NameComponent,
    PlayerSlotComponent,
    QuadComponent,
    RigidBodyComponent,
    TextComponent,
    TransformComponent,
    ScriptComponent,
};

pub const ComponentPanelList = [_]type{
    AISlotComponent,
    AudioComponent,
    CameraComponent,
    ColliderComponent,
    UUIDComponent,
    MicComponent,
    NameComponent,
    PlayerSlotComponent,
    QuadComponent,
    RigidBodyComponent,
    TextComponent,
    TransformComponent,
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
    UUIDComponent = UUIDComponent.Ind,
    MicComponent = MicComponent.Ind,
    NameComponent = NameComponent.Ind,
    PlayerSlotComponent = PlayerSlotComponent.Ind,
    QuadComponent = QuadComponent.Ind,
    RigidBodyComponent = RigidBodyComponent.Ind,
    EntitySceneComponent = EntitySceneComponent.Ind,
    TextComponent = TextComponent.Ind,
    TransformComponent = TransformComponent.Ind,
    ScriptComponent = ScriptComponent.Ind,
    OnInputPressedScript = OnInputPressedScript.Ind,
    OnUpdateScript = OnUpdateScript.Ind,
};

comptime {
    for (ComponentsList) |component_type| {
        const type_name = std.fmt.comptimePrint(" {s}\n", .{@typeName(component_type)});
        if (!@hasDecl(component_type, "Editable")) {
            @compileError("Type must have 'Editable' pub const declaration " ++ type_name);
        }

        if (component_type.Editable) { //if it is editable ensure that the signature is correct

            if (!std.meta.hasFn(component_type, "EditorRender")) {
                @compileError("Type must have 'EditorRender' member function is type is marked Editable " ++ type_name);
            }

            const editorrender_info = @typeInfo(@TypeOf(component_type.EditorRender));
            if (editorrender_info != .@"fn") {
                @compileError("Type's EditorRender must be a function " ++ type_name);
            }

            const fn_info = editorrender_info.@"fn";
            if (fn_info.params.len != 2) {
                @compileError("Type's EditorRender must have 2 parameters " ++ type_name);
            }

            const first_param = fn_info.params[0].type.?;
            if (first_param != *component_type) {
                @compileError("Type's EditorRender first parameter must be *type " ++ type_name);
            }

            const second_param = fn_info.params[1].type.?;
            if (second_param != *EngineContext) {
                @compileError("Type's EditorRender second paramter must be *EngineContext " ++ type_name);
            }

            const return_type = fn_info.return_type.?;
            const return_info = @typeInfo(return_type);
            if (return_info != .error_union) {
                @compileError("Type's EditorRender return type must be error union " ++ type_name);
            }

            const payload_type = return_info.error_union.payload;
            if (payload_type != void) {
                @compileError("Type's EditorRender payload must be void " ++ type_name);
            }
        }
    }
}
