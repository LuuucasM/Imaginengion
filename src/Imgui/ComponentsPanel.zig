const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const ComponentsPanel = @This();

_P_Open: bool = true,
//HoveredEntity

pub fn Init(self: *ComponentsPanel) void {
    self._P_Open = true;
}

pub fn OnImguiRender(self: ComponentsPanel) void {
    if (self._P_Open == true) {
        _ = imgui.igBegin("Components", null, 0);
        imgui.igEnd();
    }
}

pub fn OnImguiEvent(self: *ComponentsPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => {
            if (self._P_Open == true) {
                self._P_Open = false;
            } else {
                self._P_Open = true;
            }
        },
    }
}
