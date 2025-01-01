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

pub fn OnImguiRender(self: CSEditorPanel) void {
    if (self.mP_Open == false) return;

    _ = imgui.igBegin("Component/Scripts Editor", null, 0);
    defer imgui.igEnd();

    const opt_fullscreen = true;
    const opt_padding = false;
    const p_open = true;
    const my_null_ptr: ?*anyopaque = null;
    var dockspace_flags = imgui.ImGuiDockNodeFlags_None;

    var window_flags = imgui.ImGuiWindowFlags_MenuBar | imgui.ImGuiWindowFlags_NoDocking;
    if (opt_fullscreen == true) {
        const viewport = imgui.igGetMainViewport();
        imgui.igSetNextWindowPos(viewport.*.WorkPos, 0, .{ .x = 0, .y = 0 });
        imgui.igSetNextWindowSize(viewport.*.WorkSize, 0);
        imgui.igSetNextWindowViewport(viewport.*.ID);
        imgui.igPushStyleVar_Float(imgui.ImGuiStyleVar_WindowRounding, 0);
        imgui.igPushStyleVar_Float(imgui.ImGuiStyleVar_WindowBorderSize, 0);
        window_flags |= imgui.ImGuiWindowFlags_NoTitleBar | imgui.ImGuiWindowFlags_NoCollapse | imgui.ImGuiWindowFlags_NoResize | imgui.ImGuiWindowFlags_NoMove;
        window_flags |= imgui.ImGuiWindowFlags_NoBringToFrontOnFocus | imgui.ImGuiWindowFlags_NoNavFocus;
    } else {
        dockspace_flags &= ~imgui.ImGuiDockNodeFlags_PassthruCentralNode;
    }

    if (dockspace_flags & imgui.ImGuiDockNodeFlags_PassthruCentralNode != 0) {
        window_flags |= imgui.ImGuiWindowFlags_NoBackground;
    }

    if (opt_padding == false) {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
    }
    _ = imgui.igBegin("EditDockspace", @ptrCast(@constCast(&p_open)), window_flags);
    if (opt_padding == false) {
        imgui.igPopStyleVar(1);
    }
    if (opt_fullscreen == true) {
        imgui.igPopStyleVar(2);
    }

    const dockspace_id = imgui.igGetID_Str("EditDockspace");
    _ = imgui.igDockSpace(dockspace_id, .{ .x = 0, .y = 0 }, dockspace_flags, @ptrCast(@alignCast(my_null_ptr)));
    defer imgui.igEnd();
    for (self.mEditorWindows.items) |window| {
        _ = window;
        //_ = imgui.igBegin("", null, 0);
        //defer imgui.igEnd();
        //window.EditorRender();
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
