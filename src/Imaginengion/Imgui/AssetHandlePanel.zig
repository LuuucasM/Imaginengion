const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const AssetManager = @import("../Assets/AssetManager.zig");
const FileMetaData = @import("../Assets/Assets/FileMetaData.zig");
const AssetHandlePanel = @This();

_P_Open: bool,

pub fn Init() AssetHandlePanel {
    return AssetHandlePanel{
        ._P_Open = false,
    };
}

pub fn OnImguiRender(self: AssetHandlePanel) !void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("AssetHandles", null, 0);
    defer imgui.igEnd();
    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file_data_set = try AssetManager.GetGroup(.{ .Component = FileMetaData }, allocator);
    for (file_data_set.items) |asset_id| {
        const file_data = try AssetManager.GetAsset(FileMetaData, asset_id);
        const text = try std.fmt.allocPrint(fba.allocator(), "Handle # {d}: \n\tPath: {s}\n", .{ asset_id, file_data.mRelPath });
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

pub fn OnTogglePanelEvent(self: *AssetHandlePanel) void {
    self._P_Open = !self._P_Open;
}
