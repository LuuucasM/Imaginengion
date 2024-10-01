const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const AssetManager = @import("../Assets/AssetManager.zig");
const AssetHandlePanel = @This();

_P_Open: bool = false,

pub fn Init(self: *AssetHandlePanel) void {
    self._P_Open = false;
}

pub fn OnImguiRender(self: AssetHandlePanel) !void {

    if (self._P_Open == false) return;
    _ = imgui.igBegin("AssetHandles", null, 0);
    defer imgui.igEnd();
    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const HandleMap = AssetManager.GetHandleMap();
    var iter = HandleMap.iterator();
    while (iter.next()) |entry| {
        const text = try std.fmt.allocPrint(fba.allocator(), "Handle # {d}: \n\tPath: {s}\n", .{ entry.key_ptr.*, entry.value_ptr._AssetPath });
        defer fba.allocator().free(text);
        imgui.igTextUnformatted(text.ptr, text.ptr + text.len);
    }
}

pub fn OnImguiEvent(self: *AssetHandlePanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelOpen(),
        else => @panic("This event has not been handled yet in ViewportPanel!\n"),
    }
}

fn OnTogglePanelOpen(self: *AssetHandlePanel) void {
    self._P_Open = !self._P_Open;
}