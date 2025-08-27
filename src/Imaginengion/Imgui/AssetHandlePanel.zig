const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const AssetManager = @import("../Assets/AssetManager.zig");
const FileMetaData = @import("../Assets/Assets/FileMetaData.zig");
const Tracy = @import("../Core/Tracy.zig");
const AssetHandlePanel = @This();

_P_Open: bool,

pub fn Init() AssetHandlePanel {
    return AssetHandlePanel{
        ._P_Open = false,
    };
}

pub fn OnImguiRender(self: AssetHandlePanel, frame_allocator: std.mem.Allocator) !void {
    const zone = Tracy.ZoneInit("AssetHandle OIR", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;
    _ = imgui.igBegin("AssetHandles", null, 0);
    defer imgui.igEnd();

    const file_data_set = try AssetManager.GetGroup(.{ .Component = FileMetaData }, frame_allocator);
    for (file_data_set.items) |asset_id| {
        const file_data = try AssetManager.GetAsset(FileMetaData, asset_id);
        const text = try std.fmt.allocPrint(frame_allocator, "Handle # {d}: \n\tPath: {s}\n", .{ asset_id, file_data.mRelPath.items });
        imgui.igTextUnformatted(text.ptr, text.ptr + text.len);
    }
}

pub fn OnImguiEvent(self: *AssetHandlePanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelOpen(),
        else => @panic("This event has not been handled yet in ViewportPanel!\n"),
    }
}

pub fn OnTogglePanelEvent(self: *AssetHandlePanel) void {
    self._P_Open = !self._P_Open;
}
