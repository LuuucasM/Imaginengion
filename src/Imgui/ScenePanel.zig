const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiManager = @import("../Imgui/Imgui.zig");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Entity = @import("../ECS/Entity.zig");
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const ScenePanel = @This();

mIsVisible: bool,
mSelectedScene: ?usize,
mSelectedEntity: ?u32,

pub fn Init() ScenePanel {
    return ScenePanel{
        .mIsVisible = true,
        .mSelectedScene = null,
        .mSelectedEntity = null,
    };
}

pub fn OnImguiRender(self: *ScenePanel, scene_stack_ref: *std.ArrayList(SceneLayer)) !void {
    if (self.mIsVisible == false) return;

    _ = imgui.igBegin("Scenes", null, 0);
    defer imgui.igEnd();
    
    var available_region: imgui.ImVec2 = undefined;
    imgui.igGetContentRegionAvail(&available_region);

    if (imgui.igBeginChild_Str("SceneChild", available_region, imgui.ImGuiChildFlags_None, imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoScrollbar)) {
        defer imgui.igEndChild();
        var i: usize = scene_stack_ref.items.len;
        while (i > 0) {
            i -= 1;
            const scene_layer = &scene_stack_ref.items[i];

            var name_buf: [260]u8 = undefined;
            const scene_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{scene_layer.mName.items});

            _ = imgui.igPushID_Str(scene_name.ptr);
            defer imgui.igPopID();

            const tree_flags = imgui.ImGuiTreeNodeFlags_OpenOnArrow;
            const is_tree_open = imgui.igTreeNodeEx_Str(scene_name.ptr, tree_flags);

            const draw_list = imgui.igGetWindowDrawList();
            var min_pos: imgui.ImVec2 = undefined;
            var max_pos: imgui.ImVec2 = undefined;
            var size: imgui.ImVec2 = undefined;
            imgui.igGetItemRectMin(&min_pos);
            imgui.igGetItemRectMax(&max_pos);
            imgui.igGetItemRectSize(&size);

            if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left) == true){
                self.mSelectedScene = scene_layer.mInternalID;
            }

            if (scene_layer.mLayerType == .OverlayLayer){
                imgui.ImDrawList_AddRect(draw_list, min_pos, max_pos, 0xFFEBCE87, 0.0, imgui.ImDrawFlags_None, 1.0);
            }
            else{
                imgui.ImDrawList_AddRect(draw_list, min_pos, max_pos, 0xFF84A4C4, 0.0, imgui.ImDrawFlags_None, 1.0);
            }

            if (self.mSelectedScene == scene_layer.mInternalID) {
                imgui.ImDrawList_AddLine(draw_list, .{.x = min_pos.x, .y = min_pos.y+size.y}, .{.x = min_pos.x + size.x, .y = min_pos.y+size.y}, 0xFFFFFFFF, 1.0);
            }

            if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                defer imgui.igEndDragDropSource();
                _ = imgui.igSetDragDropPayload("SceneLayerMove", @ptrCast(&scene_layer.mInternalID), @sizeOf(usize), imgui.ImGuiCond_Once);
            }

            if (imgui.igBeginDragDropTarget() == true) {
                defer imgui.igEndDragDropTarget();
                if (imgui.igAcceptDragDropPayload("SceneLayerMove", imgui.ImGuiDragDropFlags_None)) |payload| {
                    const payload_internal_id = @as(*usize, @ptrCast(@alignCast(payload.*.Data))).*;
                    const payload_scene = scene_stack_ref.items[payload_internal_id];
                    const current_pos = payload_scene.mInternalID;
                    const new_pos = i;
                    if (new_pos < current_pos) {
                        std.mem.copyBackwards(SceneLayer, scene_stack_ref.items[new_pos + 1 .. current_pos+1], scene_stack_ref.items[new_pos .. current_pos]);

                        for (scene_stack_ref.items[new_pos + 1 .. current_pos+1]) |*drag_scene_layer| {
                            drag_scene_layer.mInternalID += 1;
                        }

                        if (self.mSelectedScene) |scene_id| {
                            if ( new_pos <= scene_id and scene_id < current_pos){
                                self.mSelectedScene.? += 1;
                            }
                        }
                    } else {
                        std.mem.copyForwards(SceneLayer, scene_stack_ref.items[current_pos .. new_pos], scene_stack_ref.items[current_pos + 1 .. new_pos+1]);

                        for (scene_stack_ref.items[current_pos .. new_pos]) |*drag_scene_layer| {
                            drag_scene_layer.mInternalID -= 1;
                        }
                        if (self.mSelectedScene) |scene_id| {
                            if ( current_pos < scene_id and scene_id <= new_pos){
                                self.mSelectedScene.? -= 1;
                            }
                        }
                    }
                    scene_stack_ref.items[i] = payload_scene;
                    scene_stack_ref.items[i].mInternalID = i;
                    if (payload_scene.mInternalID == self.mSelectedScene) {
                        self.mSelectedScene = i;
                    }
                }
            }

            if (is_tree_open){
                var entity_iter = scene_layer.mEntityIDs.iterator();
                while (entity_iter.next()) |entity_id| {
                    const entity = Entity{ .mEntityID = entity_id.key_ptr.*, .mSceneLayerRef = scene_layer };
                    const entity_name = entity.GetName();
                    if (imgui.igSelectable_Bool(entity_name.ptr, false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
                        std.debug.print("clicked on entity name: {s}", .{entity_name});
                    }
                }
                imgui.igTreePop();
            }
        }
    }
    if (imgui.igBeginDragDropTarget() == true){
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload("SceneLayerLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            const new_event = ImguiEvent{
                .ET_OpenSceneEvent = .{
                    .Path = try ImguiManager.EventAllocator().dupe(u8, path),
                },
            };
            try ImguiManager.InsertEvent(new_event);
        }
    }
}

pub fn OnTogglePanelEvent(self: *ScenePanel) void {
    self.mIsVisible = !self.mIsVisible;
}
