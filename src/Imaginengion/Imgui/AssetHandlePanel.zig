const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const FileMetaData = @import("../Assets/Assets/FileMetaData.zig");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const AssetHandlePanel = @This();

_P_Open: bool = false,

pub fn Init(self: AssetHandlePanel) void {
    _ = self;
}

pub fn OnImguiRender(self: AssetHandlePanel, engine_context: EngineContext) !void {
    const zone = Tracy.ZoneInit("AssetHandle OIR", @src());
    defer zone.Deinit();

    const frame_allocator = engine_context.mFrameAllocator;

    if (self._P_Open == false) return;
    _ = imgui.igBegin("AssetHandles", null, 0);
    defer imgui.igEnd();

    const file_data_set = try engine_context.mAssetManager.GetGroup(.{ .Component = FileMetaData }, frame_allocator);
    for (file_data_set.items) |asset_id| {
        const file_data = try engine_context.mAssetManager.GetAsset(FileMetaData, asset_id);
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
