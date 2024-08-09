const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const StatsPanel = @This();

_P_Open: bool = true,

pub fn Init(self: *StatsPanel) void {
    self._P_Open = true;
}

pub fn OnImguiRender(self: StatsPanel) void {
    if (self._P_Open == true) {
        _ = imgui.igBegin("Stats", null, 0);
        imgui.igEnd();
    }
}

pub fn OnImguiEvent(self: *StatsPanel, event: *ImguiEvent) void {
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
