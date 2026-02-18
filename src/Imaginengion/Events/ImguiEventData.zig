const Entity = @import("../GameObjects/Entity.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const EditorState = @import("../Imgui/ToolbarPanel.zig").EditorState;

pub const EventCategories = enum {
    RenderEnd,
};

pub const Event = union(enum) {
    DefaultEvent: DefaultEvent,
    MoveSceneEvent: MoveSceneEvent,
    SelectSceneEvent: SelectSceneEvent,
    SelectEntityEvent: SelectEntityEvent,
    ViewportResizeEvent: ViewportResizeEvent,
    PlayPanelResizeEvent: PlayPanelResizeEvent,
    ChangeEditorStateEvent: ChangeEditorStateEvent,
    OpenSceneSpecEvent: OpenSceneSpecEvent,
    DeleteEntityEvent: DeleteEntityEvent,
    DeleteSceneEvent: DeleteSceneEvent,
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

pub const ChangeEditorStateEvent = struct {
    mEditorState: EditorState,
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
