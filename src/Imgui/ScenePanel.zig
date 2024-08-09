const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const ScenePanel = @This();

_P_Open: bool = true,

pub fn Init(self: *ScenePanel) void {
    self._P_Open = true;
}

pub fn OnImguiRender(self: ScenePanel) void {
    if (self._P_Open == true) {
        _ = imgui.igBegin("Scene", null, 0);
        imgui.igEnd();
    }
}
pub fn OnImguiEvent(self: *ScenePanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_DockspaceWindowEvent => {
            if (self._P_Open == true) {
                self._P_Open = false;
            } else {
                self._P_Open = true;
            }
        },
        //else => {
        //    @panic("This event is not supported in scene yet");
        //},
    }
}
