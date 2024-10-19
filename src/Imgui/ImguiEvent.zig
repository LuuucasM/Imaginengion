const LayerType = @import("../ECS/Components/SceneIDComponent.zig").ELayerType;

pub const PanelType = enum(u16) {
    AssetHandles,
    Components,
    ContentBrowser,
    Properties,
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
};

pub const DefaultEvent = struct {};

pub const TogglePanelEvent = struct {
    _PanelType: PanelType,
};

pub const NewProjectEvent = struct {
    _Path: []const u8,
};

pub const OpenProjectEvent = struct {
    _Path: []const u8,
};

pub const NewSceneEvent = struct {
    mLayerType: LayerType,
};