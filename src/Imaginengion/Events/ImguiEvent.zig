const LayerType = @import("../Scene/SceneComponents.zig").SceneComponent.LayerType;
const Entity = @import("../GameObjects/Entity.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const SceneType = @import("../Scene/SceneLayer.zig").Type;
const EditorWindow = @import("../Imgui/EditorWindow.zig");
const Vec2f32 = @import("../Math/LinAlg.zig").Vec2f32;
const ScriptType = @import("../Assets/Assets.zig").ScriptAsset.ScriptType;
const EditorState = @import("../Imgui/ToolbarPanel.zig").EditorState;

pub const PanelType = enum(u4) {
    Default = 0,
    AssetHandles = 1,
    Components = 2,
    ContentBrowser = 3,
    CSEditor = 4,
    PlayPanel = 5,
    Scene = 6,
    Scripts = 7,
    Stats = 8,
    Viewport = 9,
};
pub const ImguiEvent = union(enum) {
    ET_DefaultEvent: DefaultEvent,
    ET_TogglePanelEvent: TogglePanelEvent,
    ET_NewProjectEvent: NewProjectEvent,
    ET_OpenProjectEvent: OpenProjectEvent,
    ET_NewSceneEvent: NewSceneEvent,
    ET_SaveSceneEvent: SaveSceneEvent,
    ET_SaveSceneAsEvent: SaveSceneAsEvent,
    ET_OpenSceneEvent: OpenSceneEvent,
    ET_MoveSceneEvent: MoveSceneEvent,
    ET_NewEntityEvent: NewEntityEvent,
    ET_SelectSceneEvent: SelectSceneEvent,
    ET_SelectEntityEvent: SelectEntityEvent,
    ET_SelectComponentEvent: SelectComponentEvent,
    ET_SelectScriptEvent: SelectScriptEvent,
    ET_ViewportResizeEvent: ViewportResizeEvent,
    ET_PlayPanelResizeEvent: PlayPanelResizeEvent,
    ET_NewScriptEvent: NewScriptEvent,
    ET_ChangeEditorStateEvent: ChangeEditorStateEvent,
    ET_OpenSceneSpecEvent: OpenSceneSpecEvent,
    ET_SaveEntityEvent: SaveEntityEvent,
    ET_SaveEntityAsEvent: SaveEntityAsEvent,
    ET_DeleteEntityEvent: DeleteEntityEvent,
    ET_DeleteSceneEvent: DeleteSceneEvent,
};

pub const DefaultEvent = struct {};

pub const TogglePanelEvent = struct {
    _PanelType: PanelType,
};

pub const NewProjectEvent = struct {
    Path: []const u8,
};

pub const OpenProjectEvent = struct {
    Path: []const u8,
};

pub const NewSceneEvent = struct {
    mLayerType: LayerType,
};

pub const SaveSceneEvent = struct {};

pub const SaveSceneAsEvent = struct {
    AbsPath: []const u8,
};

pub const OpenSceneEvent = struct {
    Path: []const u8,
};

pub const MoveSceneEvent = struct {
    SceneID: SceneType,
    NewPos: usize,
};

pub const NewEntityEvent = struct {
    SceneID: SceneType,
};

pub const SelectSceneEvent = struct {
    SelectedScene: ?SceneLayer,
};

pub const SelectEntityEvent = struct {
    SelectedEntity: ?Entity,
};

pub const SelectComponentEvent = struct {
    mEditorWindow: EditorWindow,
};

pub const SelectScriptEvent = struct {
    mEditorWindow: EditorWindow,
};

pub const ViewportResizeEvent = struct {
    mWidth: usize,
    mHeight: usize,
};

pub const PlayPanelResizeEvent = struct {
    mWidth: usize,
    mHeight: usize,
};

pub const NewScriptEvent = struct {
    mScriptType: ScriptType,
};

pub const ChangeEditorStateEvent = struct {
    mEditorState: EditorState,
    mStartEntity: ?Entity,
};

pub const OpenSceneSpecEvent = struct {
    mSceneLayer: SceneLayer,
};

pub const SaveEntityEvent = struct {};

pub const SaveEntityAsEvent = struct {
    Path: []const u8,
};

pub const DeleteEntityEvent = struct {
    mEntity: Entity,
};

pub const DeleteSceneEvent = struct {
    mScene: SceneLayer,
};
