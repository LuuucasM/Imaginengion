const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const Entity = @import("../GameObjects/Entity.zig");
const EditorWindow = @import("EditorWindow.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const Tracy = @import("../Core/Tracy.zig");
const CSEditorPanel = @This();

mP_Open: bool = true,
mEditorWindows: std.AutoArrayHashMap(u64, EditorWindow) = undefined,

pub fn Init(self: *CSEditorPanel, engine_allocator: std.mem.Allocator) void {
    self.mEditorWindows = std.AutoArrayHashMap(u64, EditorWindow).init(engine_allocator);
}

pub fn Deinit(self: *CSEditorPanel) void {
    self.mEditorWindows.deinit();
}

pub fn OnImguiRender(self: *CSEditorPanel, frame_allocator: std.mem.Allocator) !void {
    const zone = Tracy.ZoneInit("CSEditor OIR", @src());
    defer zone.Deinit();

    if (self.mP_Open == false) return;

    const my_null_ptr: ?*anyopaque = null;

    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });

    _ = imgui.igBegin("Component/Script Editor", null, 0);
    defer imgui.igEnd();
    imgui.igPopStyleVar(1);

    const dockspace_id = imgui.igGetID_Str("EditorDockspace");
    _ = imgui.igDockSpace(dockspace_id, .{ .x = 0, .y = 0 }, 0, @ptrCast(@alignCast(my_null_ptr)));

    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const fba_allocator = fba.allocator();

    var to_remove = std.ArrayList(u64){};
    defer to_remove.deinit(fba_allocator);

    var iter = self.mEditorWindows.iterator();
    while (iter.next()) |entry| {
        const id_name = entry.key_ptr.*;
        const editor_window = entry.value_ptr;

        const entity_name = editor_window.mEntity.GetName();
        const component_name = editor_window.GetComponentName();

        const name_len = std.mem.indexOf(u8, entity_name, &.{0}) orelse entity_name.len; // Find first null byte or use full length
        const trimmed_name = entity_name[0..name_len];

        const name = try std.fmt.allocPrint(fba_allocator, "{s} - {s}###{d}\x00", .{ trimmed_name, component_name, id_name });
        defer fba_allocator.free(name);

        imgui.igSetNextWindowDockID(dockspace_id, imgui.ImGuiCond_Once);

        var is_open = true;
        _ = imgui.igBegin(name.ptr, &is_open, 0);
        defer imgui.igEnd();
        try editor_window.EditorRender(frame_allocator);

        if (is_open == false) {
            try to_remove.append(fba_allocator, id_name);
        }
    }

    for (to_remove.items) |id| {
        _ = self.mEditorWindows.orderedRemove(id);
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
    const entity_id = new_editor_window.mEntity.mEntityID;
    const component_id = new_editor_window.GetComponentID();

    const key: u64 = (@as(u64, entity_id) << 32) | component_id;

    if (self.mEditorWindows.contains(key) == false) {
        try self.mEditorWindows.put(key, new_editor_window);
    }
}

pub fn OnSelectScriptEvent(self: *CSEditorPanel, new_editor_window: EditorWindow) !void {
    const entity_id = new_editor_window.mEntity.mEntityID;
    const component_id = new_editor_window.GetComponentID();

    const key: u64 = (@as(u64, entity_id) << 32) | component_id;

    if (self.mEditorWindows.contains(key) == false) {
        try self.mEditorWindows.put(key, new_editor_window);
    }
}

pub fn RmEntityComp(self: *CSEditorPanel, component_ptr: *anyopaque) !void {
    var iter = self.mEditorWindows.iterator();
    while (iter.next()) |entry| {
        const id_name = entry.key_ptr.*;
        const editor_window = entry.value_ptr;
        if (editor_window.mPtr == component_ptr) {
            //this will invalidate iter but we know there is only 1 possible so we can return here
            _ = self.mEditorWindows.orderedRemove(id_name);
            return;
        }
    }
}
