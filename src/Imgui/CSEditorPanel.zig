const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const Entity = @import("../ECS/Entity.zig");
const EditorWindow = @import("EditorWindow.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const CSEditorPanel = @This();

mP_Open: bool,
mEditorWindows: std.ArrayList(EditorWindow),
var EditorWindowsGPA = std.heap.GeneralPurposeAllocator(.{}){};

pub fn Init() CSEditorPanel {
    return CSEditorPanel{
        .mP_Open = true,
        .mEditorWindows = std.ArrayList(EditorWindow).init(EditorWindowsGPA.allocator()),
    };
}

pub fn OnImguiRender(self: CSEditorPanel) !void {
    if (self.mP_Open == false) return;

    const p_open = true;
    const my_null_ptr: ?*anyopaque = null;

    const dockspace_flags = imgui.ImGuiDockNodeFlags_None;
    const window_flags = imgui.ImGuiWindowFlags_None;

    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });

    _ = imgui.igBegin("Component/Script Editor", @ptrCast(@constCast(&p_open)), window_flags);
    defer imgui.igEnd();
    imgui.igPopStyleVar(1);

    const dockspace_id = imgui.igGetID_Str("EditorDockspace");
    _ = imgui.igDockSpace(dockspace_id, .{ .x = 0, .y = 0 }, dockspace_flags, @ptrCast(@alignCast(my_null_ptr)));

    var buffer: [400]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    for (self.mEditorWindows.items) |window| {
        const name = try std.fmt.allocPrint(fba.allocator(), "{s} - {s}", .{ window.mEntity.GetName(), window.GetComponentName() });
        defer fba.allocator().free(name);
        defer fba.reset();

        std.debug.print("testing name: {s}\n", .{name});
        imgui.igSetNextWindowDockID(dockspace_id, imgui.ImGuiCond_Once);

        _ = imgui.igBegin(name.ptr, null, 0);
        defer imgui.igEnd();
        try window.EditorRender();
    }
}

pub fn OnImguiEvent(self: *CSEditorPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("This event isnt handled yet in Component/Scripts Editor Panel!\n"),
    }
}

pub fn OnTogglePanelEvent(self: *CSEditorPanel) void {
    self.mP_Open = !self.mP_Open;
}

pub fn OnSelectComponentEvent(self: *CSEditorPanel, new_editor_window: EditorWindow) !void {
    try self.mEditorWindows.append(new_editor_window);
}

pub fn OnSelectScriptEvent(self: *CSEditorPanel, new_editor_window: EditorWindow) !void {
    try self.mEditorWindows.append(new_editor_window);
}
