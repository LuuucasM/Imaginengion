const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const AssetManager = @import("../Assets/AssetManager.zig");
const AssetHandlePanel = @This();

_P_Open: bool = false,

pub fn Init(self: *AssetHandlePanel) !void {
    self._P_Open = false;
}

pub fn OnImguiRender(self: AssetHandlePanel) !void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("AssetHandles", null, 0);
    defer imgui.igEnd();
    //get an iterator for the id to handle map in the asset manager
    if (AssetManager.GetNumHandles() > 0) {
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
    //go through each entry and print the handles id and path
}

pub fn OnImguiEvent(self: *AssetHandlePanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self._P_Open = !self._P_Open,
        else => @panic("This event has not been handled yet in ViewportPanel!\n"),
    }
}
