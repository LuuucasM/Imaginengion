const ListInd = @import("../ECS/Components.zig").ListInd;
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");

pub const AISlotComponent = @import("Entity/AISlotComponent.zig");
pub const AudioComponent = @import("Entity/AudioComponent.zig");
pub const ColliderComponent = @import("Entity/ColliderComponent.zig");
pub const UUIDComponent = @import("Shared/UUIDComponent.zig");
pub const NameComponent = @import("Shared/NameComponent.zig");
pub const PlayerSlotComponent = @import("Entity/PlayerSlotComponent.zig");
pub const QuadComponent = @import("Entity/QuadComponent.zig");
pub const RigidBodyComponent = @import("Entity/RigidBodyComponent.zig");
pub const StaticBodyTag = @import("Entity/TagComponents.zig").StaticBodyTag;
pub const DynamicBodyTag = @import("Entity/TagComponents.zig").DynamicBodyTag;
pub const KinematicBodyTag = @import("Entity/TagComponents.zig").KinematicBodyTag;
pub const LayoutDirtyTag = @import("Entity/TagComponents.zig").LayoutDirtyTag;
pub const LayoutHiddenTag = @import("Entity/TagComponents.zig").LayoutHiddenTag;
pub const HoveredTag = @import("Entity/TagComponents.zig").HoveredTag;
pub const PressedTag = @import("Entity/TagComponents.zig").PressedTag;
pub const DropHoverTag = @import("Entity/TagComponents.zig").DropHoverTag;
pub const DragSourceComponent = @import("Entity/DragSourceComponent.zig");
pub const DropTargetComponent = @import("Entity/DropTargetComponent.zig");
pub const FocusedTag = @import("Entity/TagComponents.zig").FocusedTag;
pub const TextInputComponent = @import("Entity/TextInputComponent.zig");
pub const PopupComponent = @import("Entity/PopupComponent.zig");
pub const LayoutComponent = @import("Entity/LayoutComponent.zig");
pub const LayoutItemComponent = @import("Entity/LayoutItemComponent.zig");
pub const EntitySceneComponent = @import("Entity/EntitySceneComponent.zig");
pub const TransformComponent = @import("Shared/TransformComponent.zig");
pub const TransformDirtyTag = @import("Shared/TagComponents.zig").TransformDirtyTag;
pub const ShouldRenderTag = @import("Shared/TagComponents.zig").ShouldRenderTag;
pub const GameLayerTag = @import("Shared/TagComponents.zig").GameLayerTag;
pub const OverlayLayerTag = @import("Shared/TagComponents.zig").OverlayLayerTag;
pub const ScriptComponent = @import("Shared/ScriptComponent.zig");
pub const TextComponent = @import("Entity/TextComponent.zig");
pub const ViewpointComponent = @import("Entity/ViewpointComponent.zig");
pub const RenderTargetComponent = @import("Shared/RenderTargetComponent.zig");
pub const TmplRefComponent = @import("Shared/TmplRefComponent.zig");

//the ECS supplies this one itself: it marks an entity as a real game object rather than a
//convenience entity that only exists to carry a bundle of components for its parent
pub const MainObjectComponent = @import("../ECS/Components.zig").MainObjectComponent;

const ScriptTags = @import("Shared/ScriptTags.zig");
pub const OnKeyPressedScript = ScriptTags.OnKeyPressedScript;
pub const OnUpdateScript = ScriptTags.EntityOnUpdateScript;
pub const OnCollisionBeginScript = ScriptTags.OnCollisionBeginScript;

///This is an array of all the components that Entity can have
/// It is used to be passed to the ECS
pub const ComponentsList = [_]type{
    //components
    AISlotComponent,
    AudioComponent,
    ColliderComponent,
    UUIDComponent,
    NameComponent,
    PlayerSlotComponent,
    QuadComponent,
    RigidBodyComponent,
    StaticBodyTag,
    KinematicBodyTag,
    DynamicBodyTag,
    EntitySceneComponent,
    TextComponent,
    TransformComponent,
    TransformDirtyTag,
    ShouldRenderTag,
    ViewpointComponent,
    RenderTargetComponent,
    TmplRefComponent,
    //never saved: an entity takes its scene's layer (Scene.CreateEntity, Entity.CreateChild)
    GameLayerTag,
    OverlayLayerTag,
    LayoutComponent,
    LayoutItemComponent,
    LayoutDirtyTag,
    LayoutHiddenTag,
    HoveredTag,
    PressedTag,
    DropHoverTag,
    DragSourceComponent,
    DropTargetComponent,
    FocusedTag,
    TextInputComponent,
    PopupComponent,

    //scripts
    ScriptComponent,
    OnKeyPressedScript,
    OnUpdateScript,
    OnCollisionBeginScript,
};

///This is an array of components that should be serialized
/// (ScriptComponent is not listed, scripts are saved separately and recreated with AddScript)
pub const SerializeList = [_]type{
    AISlotComponent,
    AudioComponent,
    ColliderComponent,
    UUIDComponent,
    RenderTargetComponent,
    MainObjectComponent,
    NameComponent,
    PlayerSlotComponent,
    QuadComponent,
    //the body type is the tag, so the tag is what is saved. Ahead of RigidBodyComponent on purpose: a rigid
    //body added with no type tag is given one, so the saved tag has to be on the entity first or it would be
    //added a second time on load (the same goes for a template being copied, which goes through this list too)
    StaticBodyTag,
    KinematicBodyTag,
    DynamicBodyTag,
    RigidBodyComponent,
    ShouldRenderTag,
    TextComponent,
    TransformComponent,
    ViewpointComponent,
    TmplRefComponent,
    LayoutComponent,
    LayoutItemComponent,
    TextInputComponent,
    PopupComponent,
};

/// What a linked copy keeps of its own when it is stripped down (see ECSObject.Core.Strip), everything
/// else in SerializeList it gets from its template
pub const ShellList = [_]type{
    UUIDComponent,
    NameComponent,
    TransformComponent,
    TmplRefComponent,
};

///This is an array of components that should be displayed
/// from the Components Panel. Also this is used for the
/// popup menu for adding components as well
pub const ComponentPanelList = [_]type{
    AISlotComponent,
    AudioComponent,
    ColliderComponent,
    UUIDComponent,
    MainObjectComponent,
    RenderTargetComponent,
    NameComponent,
    PlayerSlotComponent,
    QuadComponent,
    RigidBodyComponent,
    ShouldRenderTag,
    TextComponent,
    TransformComponent,
    ViewpointComponent,
    TmplRefComponent,
    LayoutComponent,
    LayoutItemComponent,
    TextInputComponent,
    PopupComponent,
};

///A list of all the scripts
pub const ScriptsList = [_]type{
    OnKeyPressedScript,
    OnUpdateScript,
    OnCollisionBeginScript,
};

pub const EComponents = enum(u16) {
    AISlotComponent = ListInd(&ComponentsList, AISlotComponent),
    AudioComponent = ListInd(&ComponentsList, AudioComponent),
    ColliderComponent = ListInd(&ComponentsList, ColliderComponent),
    UUIDComponent = ListInd(&ComponentsList, UUIDComponent),
    NameComponent = ListInd(&ComponentsList, NameComponent),
    PlayerSlotComponent = ListInd(&ComponentsList, PlayerSlotComponent),
    QuadComponent = ListInd(&ComponentsList, QuadComponent),
    RigidBodyComponent = ListInd(&ComponentsList, RigidBodyComponent),
    StaticBodyTag = ListInd(&ComponentsList, StaticBodyTag),
    DynamicBodyTag = ListInd(&ComponentsList, DynamicBodyTag),
    KinematicBodyTag = ListInd(&ComponentsList, KinematicBodyTag),
    EntitySceneComponent = ListInd(&ComponentsList, EntitySceneComponent),
    TextComponent = ListInd(&ComponentsList, TextComponent),
    TransformComponent = ListInd(&ComponentsList, TransformComponent),
    TransformDirtyTag = ListInd(&ComponentsList, TransformDirtyTag),
    ShouldRenderTag = ListInd(&ComponentsList, ShouldRenderTag),
    ScriptComponent = ListInd(&ComponentsList, ScriptComponent),
    OnInputPressedScript = ListInd(&ComponentsList, OnKeyPressedScript),
    OnUpdateScript = ListInd(&ComponentsList, OnUpdateScript),
    OnCollisionBeginScript = ListInd(&ComponentsList, OnCollisionBeginScript),
    ViewpointComponent = ListInd(&ComponentsList, ViewpointComponent),
    RenderTargetComponent = ListInd(&ComponentsList, RenderTargetComponent),
    TmplRefComponent = ListInd(&ComponentsList, TmplRefComponent),
    GameLayerTag = ListInd(&ComponentsList, GameLayerTag),
    OverlayLayerTag = ListInd(&ComponentsList, OverlayLayerTag),
    LayoutComponent = ListInd(&ComponentsList, LayoutComponent),
    LayoutItemComponent = ListInd(&ComponentsList, LayoutItemComponent),
    LayoutDirtyTag = ListInd(&ComponentsList, LayoutDirtyTag),
    LayoutHiddenTag = ListInd(&ComponentsList, LayoutHiddenTag),
    HoveredTag = ListInd(&ComponentsList, HoveredTag),
    PressedTag = ListInd(&ComponentsList, PressedTag),
    DropHoverTag = ListInd(&ComponentsList, DropHoverTag),
    DragSourceComponent = ListInd(&ComponentsList, DragSourceComponent),
    DropTargetComponent = ListInd(&ComponentsList, DropTargetComponent),
    FocusedTag = ListInd(&ComponentsList, FocusedTag),
    TextInputComponent = ListInd(&ComponentsList, TextInputComponent),
    PopupComponent = ListInd(&ComponentsList, PopupComponent),
};

comptime {
    for (ComponentsList) |component_type| {
        const type_name = " " ++ @typeName(component_type) ++ "\n";
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
            if (fn_info.param_types.len != 2) {
                @compileError("Type's EditorRender must have 2 parameters " ++ type_name);
            }

            const first_param = fn_info.param_types[0].?;
            if (first_param != *component_type) {
                @compileError("Type's EditorRender first parameter must be *type " ++ type_name);
            }

            const second_param = fn_info.param_types[1].?;
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

    for (ScriptsList) |script_type| {
        const type_name = " " ++ @typeName(script_type) ++ "\n";
        if (!@hasDecl(script_type, "Scripttype")) {
            @compileError("Type must have 'Scripttype' pub const declaration " ++ type_name);
        }
    }
}
