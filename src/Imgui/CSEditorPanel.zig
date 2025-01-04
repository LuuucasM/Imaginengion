const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const Entity = @import("../ECS/Entity.zig");
const EditorWindow = @import("EditorWindow.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const CSEditorPanel = @This();

mP_Open: bool,
mEditorWindows: std.StringArrayHashMap(EditorWindow),
var EditorWindowsGPA = std.heap.GeneralPurposeAllocator(.{}){};

pub fn Init() CSEditorPanel {
    return CSEditorPanel{
        .mP_Open = true,
        .mEditorWindows = std.StringArrayHashMap(EditorWindow).init(EditorWindowsGPA.allocator()),
    };
}

pub fn Deinit(self: *CSEditorPanel) void {
    //TODO: deallocate all of the keysin mEditorWindows
    self.mEditorWindows.deinit();
    EditorWindowsGPA.deinit();
}

pub fn OnImguiRender(self: CSEditorPanel) !void {
    if (self.mP_Open == false) return;

    const my_null_ptr: ?*anyopaque = null;

    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });

    _ = imgui.igBegin("Component/Script Editor", null, 0);
    defer imgui.igEnd();
    imgui.igPopStyleVar(1);

    const dockspace_id = imgui.igGetID_Str("EditorDockspace");
    _ = imgui.igDockSpace(dockspace_id, .{ .x = 0, .y = 0 }, 0, @ptrCast(@alignCast(my_null_ptr)));

    var buffer: [300]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var iter = self.mEditorWindows.iterator();
    while (iter.next()) |entry| {
        const id_name = entry.key_ptr.*;
        const window = entry.value_ptr;

        const entity_name = window.mEntity.GetName();
        const component_name = window.GetComponentName();

        const name_len = std.mem.indexOf(u8, entity_name, &.{0}) orelse entity_name.len; // Find first null byte or use full length
        const trimmed_name = entity_name[0..name_len];

        const name = try std.fmt.allocPrint(fba.allocator(), "{s} - {s}###{s}0", .{ trimmed_name, component_name, id_name });
        name[name.len - 1] = 0;
        defer fba.allocator().free(name);
        defer fba.reset();
        //std.debug.print("name: {s}\n", .{name});
        std.debug.print("name: {s}\n", .{id_name});
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
    const id_name = try std.fmt.allocPrint(EditorWindowsGPA.allocator(), "{d}{s}", .{ new_editor_window.mEntity.mEntityID, new_editor_window.GetComponentName() });
    std.debug.print("id_name: {s}\n", .{id_name});
    if (self.mEditorWindows.contains(id_name) == false) {
        try self.mEditorWindows.put(id_name, new_editor_window);
    }
}

pub fn OnSelectScriptEvent(self: *CSEditorPanel, new_editor_window: EditorWindow) !void {
    const id_name = try std.fmt.allocPrint(EditorWindowsGPA.allocator(), "{d}{s}", .{ new_editor_window.mEntity.mEntityID, new_editor_window.GetComponentName() });

    if (self.mEditorWindows.contains(id_name) == false) {
        try self.mEditorWindows.put(id_name, new_editor_window);
    }
}
