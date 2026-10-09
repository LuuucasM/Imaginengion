const ListInd = @import("../ECS/Components.zig").ListInd;
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");

pub const AISlotComponent = @import("Entity/AISlotComponent.zig");
pub const AttribComponent = @import("Shared/AttribComponent.zig");
pub const AudioComponent = @import("Entity/AudioComponent.zig");
pub const ColliderComponent = @import("Entity/ColliderComponent.zig");
pub const ConstantForceComponent = @import("Entity/ConstantForceComponent.zig");
pub const UUIDComponent = @import("Shared/UUIDComponent.zig");
pub const NameComponent = @import("Shared/NameComponent.zig");
pub const PlayerSlotComponent = @import("Entity/PlayerSlotComponent.zig");
pub const ShapeComponent = @import("Entity/ShapeComponent.zig");
pub const SurfaceComponent = @import("Entity/SurfaceComponent.zig");
pub const MergeComponent = @import("Entity/MergeComponent.zig");
pub const CombineOpComponent = @import("Entity/CombineOpComponent.zig");
pub const RigidBodyComponent = @import("Entity/RigidBodyComponent.zig");
pub const StaticBodyTag = @import("Entity/TagComponents.zig").StaticBodyTag;
pub const DynamicBodyTag = @import("Entity/TagComponents.zig").DynamicBodyTag;
pub const KinematicBodyTag = @import("Entity/TagComponents.zig").KinematicBodyTag;
pub const LayoutDirtyTag = @import("Entity/TagComponents.zig").LayoutDirtyTag;
pub const LayoutHiddenTag = @import("Entity/TagComponents.zig").LayoutHiddenTag;
pub const HoveredTag = @import("Entity/TagComponents.zig").HoveredTag;
pub const PressedTag = @import("Entity/TagComponents.zig").PressedTag;
pub const DropHoverTag = @import("Entity/TagComponents.zig").DropHoverTag;
pub const SelectedTag = @import("Entity/TagComponents.zig").SelectedTag;
pub const DisabledTag = @import("Entity/TagComponents.zig").DisabledTag;
pub const DragSourceComponent = @import("Entity/DragSourceComponent.zig");
pub const DropTargetComponent = @import("Entity/DropTargetComponent.zig");
pub const FileRefComponent = @import("Entity/FileRefComponent.zig");
pub const ObjectRefComponent = @import("Entity/ObjectRefComponent.zig");
pub const FocusedTag = @import("Entity/TagComponents.zig").FocusedTag;
pub const MaskComponent = @import("Entity/MaskComponent.zig");
pub const ViewportComponent = @import("Entity/ViewportComponent.zig");
pub const UIElementComponent = @import("Entity/UIElementComponent.zig");
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
pub const OnPointerEventScript = ScriptTags.OnPointerEventScript;
pub const OnUIEventScript = ScriptTags.OnUIEventScript;
pub const OnCollisionEndScript = ScriptTags.OnCollisionEndScript;
pub const OnPreSolveScript = ScriptTags.OnPreSolveScript;
pub const OnPhysicsUpdateScript = ScriptTags.EntityOnPhysicsUpdateScript;

///This is an array of all the components that Entity can have
/// It is used to be passed to the ECS
pub const ComponentsList = [_]type{
    //components
    AISlotComponent,
    AttribComponent,
    AudioComponent,
    ColliderComponent,
    ConstantForceComponent,
    UUIDComponent,
    NameComponent,
    PlayerSlotComponent,
    ShapeComponent,
    SurfaceComponent,
    MergeComponent,
    CombineOpComponent,
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
    SelectedTag,
    DisabledTag,
    DragSourceComponent,
    DropTargetComponent,
    FileRefComponent,
    ObjectRefComponent,
    FocusedTag,
    MaskComponent,
    UIElementComponent,
    //never saved yet: the editor makes its viewports in code
    ViewportComponent,

    //scripts
    ScriptComponent,
    OnKeyPressedScript,
    OnUpdateScript,
    OnCollisionBeginScript,
    OnPointerEventScript,
    OnUIEventScript,
    OnCollisionEndScript,
    OnPreSolveScript,
    OnPhysicsUpdateScript,
};

///This is an array of components that should be serialized
/// (ScriptComponent is not listed, scripts are saved separately and recreated with AddScript)
pub const SerializeList = [_]type{
    AISlotComponent,
    AttribComponent,
    AudioComponent,
    ColliderComponent,
    ConstantForceComponent,
    UUIDComponent,
    RenderTargetComponent,
    MainObjectComponent,
    NameComponent,
    PlayerSlotComponent,
    ShapeComponent,
    SurfaceComponent,
    MergeComponent,
    CombineOpComponent,
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
    MaskComponent,
    UIElementComponent,
    DisabledTag,
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
    AttribComponent,
    AudioComponent,
    ColliderComponent,
    ConstantForceComponent,
    UUIDComponent,
    MainObjectComponent,
    RenderTargetComponent,
    NameComponent,
    PlayerSlotComponent,
    ShapeComponent,
    SurfaceComponent,
    MergeComponent,
    CombineOpComponent,
    RigidBodyComponent,
    ShouldRenderTag,
    TextComponent,
    TransformComponent,
    ViewpointComponent,
    TmplRefComponent,
    LayoutComponent,
    LayoutItemComponent,
    MaskComponent,
    UIElementComponent,
    DisabledTag,
};

///A list of all the scripts
pub const ScriptsList = [_]type{
    OnKeyPressedScript,
    OnUpdateScript,
    OnCollisionBeginScript,
    OnPointerEventScript,
    OnUIEventScript,
    OnCollisionEndScript,
    OnPreSolveScript,
    OnPhysicsUpdateScript,
};

pub const EComponents = enum(u16) {
    AISlotComponent = ListInd(&ComponentsList, AISlotComponent),
    AttribComponent = ListInd(&ComponentsList, AttribComponent),
    AudioComponent = ListInd(&ComponentsList, AudioComponent),
    ColliderComponent = ListInd(&ComponentsList, ColliderComponent),
    ConstantForceComponent = ListInd(&ComponentsList, ConstantForceComponent),
    UUIDComponent = ListInd(&ComponentsList, UUIDComponent),
    NameComponent = ListInd(&ComponentsList, NameComponent),
    PlayerSlotComponent = ListInd(&ComponentsList, PlayerSlotComponent),
    ShapeComponent = ListInd(&ComponentsList, ShapeComponent),
    SurfaceComponent = ListInd(&ComponentsList, SurfaceComponent),
    MergeComponent = ListInd(&ComponentsList, MergeComponent),
    CombineOpComponent = ListInd(&ComponentsList, CombineOpComponent),
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
    OnPointerEventScript = ListInd(&ComponentsList, OnPointerEventScript),
    OnUIEventScript = ListInd(&ComponentsList, OnUIEventScript),
    OnCollisionEndScript = ListInd(&ComponentsList, OnCollisionEndScript),
    OnPreSolveScript = ListInd(&ComponentsList, OnPreSolveScript),
    OnPhysicsUpdateScript = ListInd(&ComponentsList, OnPhysicsUpdateScript),
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
    SelectedTag = ListInd(&ComponentsList, SelectedTag),
    DisabledTag = ListInd(&ComponentsList, DisabledTag),
    DragSourceComponent = ListInd(&ComponentsList, DragSourceComponent),
    DropTargetComponent = ListInd(&ComponentsList, DropTargetComponent),
    FileRefComponent = ListInd(&ComponentsList, FileRefComponent),
    ObjectRefComponent = ListInd(&ComponentsList, ObjectRefComponent),
    FocusedTag = ListInd(&ComponentsList, FocusedTag),
    MaskComponent = ListInd(&ComponentsList, MaskComponent),
    ViewportComponent = ListInd(&ComponentsList, ViewportComponent),
    UIElementComponent = ListInd(&ComponentsList, UIElementComponent),
};

comptime {
    for (ComponentsList) |component_type| {
        const type_name = " " ++ @typeName(component_type) ++ "\n";
        if (!@hasDecl(component_type, "Editable")) {
            @compileError("Type must have 'Editable' pub const declaration " ++ type_name);
        }
    }

    for (ScriptsList) |script_type| {
        const type_name = " " ++ @typeName(script_type) ++ "\n";
        if (!@hasDecl(script_type, "Scripttype")) {
            @compileError("Type must have 'Scripttype' pub const declaration " ++ type_name);
        }
    }
}
