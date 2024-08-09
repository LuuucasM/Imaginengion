const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const ViewportPanel = @This();

_P_Open: bool = true,

pub fn Init(self: *ViewportPanel) void {
    self._P_Open = true;
}

pub fn OnImguiRender(self: ViewportPanel) void {
    if (self._P_Open == true) {
        _ = imgui.igBegin("Viewport", null, 0);
        imgui.igEnd();
    }
}

pub fn OnImguiEvent(self: *ViewportPanel, event: *ImguiEvent) void {
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
