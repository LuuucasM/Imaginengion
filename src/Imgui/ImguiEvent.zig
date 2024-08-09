pub const PanelType = enum(u16) {
    Scene,
};
pub const ImguiEvent = union(enum) {
    ET_DockspaceWindowEvent: DockspaceWindowEvent,
    pub fn GetPanelType(self: ImguiEvent) PanelType {
        switch (self) {
            inline else => |event| return event.GetPanelType(),
        }
    }
};

pub const DockspaceWindowEvent = struct {
    _PanelType: PanelType,
    pub fn GetPanelType(self: DockspaceWindowEvent) PanelType {
        return self._PanelType;
    }
};
