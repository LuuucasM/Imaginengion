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
mSceneStackRef: *const SparseSet(.{
    .SparseT = u128,
    .DenseT = u8,
    .ValueT = SceneLayer,
    .allow_resize = .ResizeAllowed,
    .value_layout = .InternalArrayOfStructs,
}),

pub fn Init(scene_stack_ref: *const SparseSet(.{
    .SparseT = u128,
    .DenseT = u8,
    .ValueT = SceneLayer,
    .allow_resize = .ResizeAllowed,
    .value_layout = .InternalArrayOfStructs,
})) ScenePanel {
    return ScenePanel{
        .mIsVisible = true,
        .mSelectedScene = null,
        .mSelectedEntity = null,
        .mSceneStackRef = scene_stack_ref,
    };
}

pub fn OnImguiRender(self: ScenePanel) void {
    if (self.mIsVisible == false) return;
    _ = imgui.igBegin("Scenes", null, 0);
    defer imgui.igEnd();

    var iter = std.mem.reverseIterator(self.mSceneStackRef.values);
    var i = self.mSceneStackRef.values.len-1;
    while (iter.next()) |scene_layer| : (i -= 1) {
        if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
            defer imgui.igEndDragDropSource();
            _ = imgui.igSetDragDropPayload("SceneLayer", @ptrCast(&scene_layer), @sizeOf(SceneLayer), imgui.ImGuiCond_Once);
        }
        if (imgui.igBeginDragDropTarget() == true){
            if (imgui.igAcceptDragDropPayload("SceneLayer", imgui.ImGuiDragDropFlags_None)) |payload|{
                defer imgui.igEndDragDropTarget();
                const payload_scene: *SceneLayer = @as(*SceneLayer, @ptrCast(@alignCast(payload.*.Data)));
                self.mSceneStackRef.Move(payload_scene.mInternalID, i);
            }
        }
        if (imgui.igTreeNode_Str(scene_layer.mName.items.ptr, imgui.ImGuiTreeNodeFlags_OpenOnArrow) == true){
            var entity_iter = scene_layer.mEntityIDs.iterator();
            while (entity_iter.next()) |entity_id|{
                const entity = Entity{.mEntityID = entity_id, .mSceneLayerRef = scene_layer};
                const name = entity.GetName();
                if (imgui.igSelectable_Bool(name, false, imgui.ImGuiSelectableFlags_None, .{.x = 0, .y = 0}) == true){
                    std.debug.print("clicked on entity name: {s}", .{name});
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

fn OnTogglePanelEvent(self: *ScenePanel) void {
    self.mIsVisible = !self.mIsVisible;
}
