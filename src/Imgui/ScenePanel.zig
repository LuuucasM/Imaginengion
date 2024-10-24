const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Entity = @import("../ECS/Entity.zig");
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const ScenePanel = @This();

mIsVisible: bool,
mSelectedScene: ?SceneLayer,
mSelectedEntity: ?Entity,

pub fn Init() ScenePanel {
    return ScenePanel{
        .mIsVisible = true,
        .mSelectedScene = null,
        .mSelectedEntity = null,
    };
}

pub fn OnImguiRender(self: ScenePanel, scene_stack_ref: *std.ArrayList(SceneLayer)) !void {
    if (self.mIsVisible == false) return;

    _ = imgui.igBegin("Scenes", null, 0);
    defer imgui.igEnd();

    var i: usize = scene_stack_ref.items.len;
    while (i > 0) {
        i -= 1;
        const scene_layer = &scene_stack_ref.items[i];
        if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
            defer imgui.igEndDragDropSource();
            _ = imgui.igSetDragDropPayload("SceneLayerMove", @ptrCast(scene_layer), @sizeOf(SceneLayer), imgui.ImGuiCond_Once);
        }
        if (imgui.igBeginDragDropTarget() == true) {
            if (imgui.igAcceptDragDropPayload("SceneLayerMove", imgui.ImGuiDragDropFlags_None)) |payload| {
                defer imgui.igEndDragDropTarget();
                const payload_scene: *SceneLayer = @as(*SceneLayer, @ptrCast(@alignCast(payload.*.Data)));
                if (payload_scene.mInternalID == i) continue;
                _ = scene_stack_ref.orderedRemove(payload_scene.mInternalID);
                try scene_stack_ref.insert(i, payload_scene.*);
            }
        }
        var name_buf: [260]u8 = undefined;
        const scene_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{scene_layer.mName.items});
        if (imgui.igTreeNodeEx_Str(scene_name.ptr, imgui.ImGuiTreeNodeFlags_OpenOnArrow) == true) {
            defer imgui.igTreePop();
            var entity_iter = scene_layer.mEntityIDs.iterator();
            while (entity_iter.next()) |entity_id| {
                const entity = Entity{ .mEntityID = entity_id.key_ptr.*, .mSceneLayerRef = scene_layer };
                const entity_name = entity.GetName();
                if (imgui.igSelectable_Bool(entity_name.ptr, false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
                    std.debug.print("clicked on entity name: {s}", .{entity_name});
                }
            }
        }
    }
}
pub fn OnImguiEvent(self: *ScenePanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("This event is handled yet in ScenePanel!\n"),
    }
}

pub fn OnTogglePanelEvent(self: *ScenePanel) void {
    self.mIsVisible = !self.mIsVisible;
}
