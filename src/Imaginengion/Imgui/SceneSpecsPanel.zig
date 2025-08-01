const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneNameComponent = SceneComponents.NameComponent;
const SceneComponent = SceneComponents.SceneComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;
const AssetHandle = @import("../Assets/AssetHandle.zig");
const Assets = @import("../Assets/Assets.zig");
const FileMetaData = Assets.FileMetaData;
const ShaderAsset = Assets.ShaderAsset;
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const SceneUtils = @import("../Scene/SceneUtils.zig");
const ImguiUtils = @import("../Imgui/ImguiUtils.zig");
const Tracy = @import("../Core/Tracy.zig");
const SceneSpecsPanel = @This();

mSceneLayer: SceneLayer,
mPOpen: bool,

pub fn Init(scene_layer: SceneLayer) !SceneSpecsPanel {
    return SceneSpecsPanel{
        .mSceneLayer = scene_layer,
        .mPOpen = true,
    };
}

pub fn OnImguiRender(self: *SceneSpecsPanel, frame_allocator: std.mem.Allocator) !void {
    const zone = Tracy.ZoneInit("Scene Specs Panel OIR", @src());
    defer zone.Deinit();

    const name_component = self.mSceneLayer.GetComponent(SceneNameComponent);

    const scene_name = try frame_allocator.dupeZ(u8, name_component.Name.items);
    imgui.igSetNextWindowSize(.{ .x = 800, .y = 600 }, imgui.ImGuiCond_Once);
    _ = imgui.igBegin(scene_name, &self.mPOpen, 0);
    defer imgui.igEnd();

    var available_region: imgui.ImVec2 = undefined;
    imgui.igGetContentRegionAvail(&available_region);

    if (imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None) == true and imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Right, false) == true) {
        imgui.igOpenPopup_Str("RightClickPopup", imgui.ImGuiPopupFlags_None);
    }
    if (imgui.igBeginPopup("RightClickPopup", imgui.ImGuiWindowFlags_None) == true) {
        defer imgui.igEndPopup();
        try ImguiUtils.SceneScriptPopupMenu();
    }
    //scene layer type
    const scene_component = self.mSceneLayer.GetComponent(SceneComponent);
    imgui.igText(@tagName(scene_component.mLayerType));

    //TODO: print all the scripts. scripts since they cant hold data they dont really have a render so just need to print they exist
    const tree_flags = imgui.ImGuiTreeNodeFlags_OpenOnArrow;
    const is_tree_open = imgui.igTreeNodeEx_Str("Scripts", tree_flags);
    if (imgui.igBeginDragDropTarget() == true) {
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload("SceneScriptLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            try SceneUtils.AddScriptToScene(self.mSceneLayer, path, .Prj);
        }
    }
    if (is_tree_open == true) {
        defer imgui.igTreePop();
        if (self.mSceneLayer.HasComponent(SceneScriptComponent) == true) {
            var curr_id = self.mSceneLayer.mSceneID;
            while (curr_id != AssetHandle.NullHandle) {
                const script_component = self.mSceneLayer.mECSManagerSCRef.GetComponent(SceneScriptComponent, curr_id);
                const file_meta_data = try script_component.mScriptAssetHandle.GetAsset(FileMetaData);
                const script_name = try frame_allocator.dupeZ(u8, std.fs.path.basename(file_meta_data.mRelPath.items));
                imgui.igText(script_name);
                curr_id = script_component.mNext;
            }
        }
    }
}
