const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const AssetManager = @import("../Assets/Assetmanager.zig");
const AssetHandlePanel = @This();

_P_Open: bool = false,

pub fn Init(self: *AssetHandlePanel) void {
    self._P_Open = false;
}

pub fn OnImguiRender(self: AssetHandlePanel) void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("AssetHandles", null, 0);
    //get an iterator for the id to handle map in the asset manager
    //go through each entry and print the handles id and path
    defer imgui.igEnd();
}

pub fn OnImguiEvent(self: *AssetHandlePanel, event: *ImguiEvent) void {
    std.debug.print("asset handle panel event turn: {}", .{!self._P_Open});
    switch (event.*) {
        .ET_TogglePanelEvent => self._P_Open = !self._P_Open,
        else => @panic("This event has not been handled yet in ViewportPanel!\n"),
    }
}
