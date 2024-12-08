const LayerType = @import("../Scene/SceneLayer.zig").LayerType;

pub const PanelType = enum {
    AssetHandles,
    Components,
    ContentBrowser,
    CSEditor,
    Scene,
    Scripts,
    Stats,
    Viewport,
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
    Path: []const u8,
};

pub const OpenSceneEvent = struct {
    Path: []const u8,
};

pub const MoveSceneEvent = struct {
    SceneID: usize,
    NewPos: usize,
};

pub const NewEntityEvent = struct {
    SceneID: usize,
};
