pub const PanelType = enum(u16) {
    Components,
    ContentBrowser,
    Properties,
    Scene,
    Scripts,
    Stats,
    Viewport,
};
pub const ImguiEvent = union(enum) {
    ET_TogglePanelEvent: TogglePanelEvent,
    pub fn GetPanelType(self: ImguiEvent) PanelType {
        switch (self) {
            inline else => |event| return event.GetPanelType(),
        }
    }
};

pub const TogglePanelEvent = struct {
    _PanelType: PanelType,
    pub fn GetPanelType(self: TogglePanelEvent) PanelType {
        return self._PanelType;
    }
};
