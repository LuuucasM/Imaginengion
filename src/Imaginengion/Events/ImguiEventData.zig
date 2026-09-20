const Entity = @import("../ECSObjects/Entity.zig");
const SceneLayer = @import("../ECSObjects/Scene.zig");
const ScriptType = @import("../ECSComponents/Asset/ScriptAsset.zig").ScriptType;
const LayerType = @import("../ECSComponents/Scene/SceneComponent.zig").LayerType;
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;

pub const EventCategories = enum {
    EndOfFrame,
};

pub const Event = union(enum) {
    DefaultEvent: DefaultEvent,
    MoveSceneEvent: MoveSceneEvent,
    SelectSceneEvent: SelectSceneEvent,
    SelectEntityEvent: SelectEntityEvent,
    ViewportResizeEvent: ViewportResizeEvent,
    PlayPanelResizeEvent: PlayPanelResizeEvent,
    OpenSceneSpecEvent: OpenSceneSpecEvent,
    DeleteEntityEvent: DeleteEntityEvent,
    DeleteSceneEvent: DeleteSceneEvent,
    NewScriptEvent: NewScriptEvent,
    NewSceneEvent: NewSceneEvent,
    SelectObjectEvent: SelectObjectEvent,
};

pub const DefaultEvent = struct {};

pub const MoveSceneEvent = struct {
    Scene: SceneLayer,
    NewPos: usize,
};

pub const SelectSceneEvent = struct {
    SelectedScene: ?SceneLayer,
};

pub const SelectEntityEvent = struct {
    SelectedEntity: ?Entity,
};

pub const ViewportResizeEvent = struct {
    mWidth: usize,
    mHeight: usize,
};

pub const PlayPanelResizeEvent = struct {
    mWidth: usize,
    mHeight: usize,
};

pub const OpenSceneSpecEvent = struct {
    mSceneLayer: SceneLayer,
};

pub const DeleteEntityEvent = struct {
    mEntity: Entity,
};

pub const DeleteSceneEvent = struct {
    mScene: SceneLayer,
};

pub const NewScriptEvent = struct {
    mScriptType: ScriptType,
};

pub const NewSceneEvent = struct {
    mLayerType: LayerType,
};

pub const SelectObjectEvent = struct {
    mObject: SelectedObject,
};
