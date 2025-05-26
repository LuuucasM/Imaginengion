const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneNameComponent = SceneComponents.NameComponent;
const SceneComponent = SceneComponents.SceneComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;
const AssetHandle = @import("../Assets/AssetHandle.zig");
const FileMetaData = @import("../Assets/Assets.zig").FileMetaData;
const SceneSpecsPanel = @This();

mScenelayer: *SceneLayer,

pub fn Init(scene_layer: *SceneLayer) !SceneSpecsPanel {
    return SceneSpecsPanel{
        .mSceneLayer = scene_layer,
    };
}

pub fn OnImguiRender(self: *SceneSpecsPanel) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const name_component = self.mScenelayer.GetComponent(SceneNameComponent);

    const scene_name = try allocator.dupeZ(u8, name_component.Name.items);
    imgui.igSetNextWindowSize(.{ .x = 800, .y = 600 }, imgui.ImGuiCond_Once);
    _ = imgui.igBegin(scene_name, null, 0);

    //const scene_component = self.mScenelayer.GetComponent(SceneComponent);

    //scene layer type
    if (imgui.igBeginCombo("Scene Type", @tagName(self.mProjectionType), imgui.ImGuiComboFlags_None) == true) {
        defer imgui.igEndCombo();
        if (imgui.igSelectable_Bool("Game Layer", if (self.mProjectionType == .Perspective) true else false, imgui.ImGuiSelectableFlags_None, imgui.ImVec2{ .x = 50, .y = 50 })) {
            //scene_component.mLayerType = .GameLayer;
            //TODO: add a way to move the layer to the section where it belongs. maybe need some imgui event?
            //maybe instead of setting the layer type here i will make an imgui event where the event will hold "NewLayerType"
            //and then the scene manager can handle
        }
        if (imgui.igSelectable_Bool("Overlay Layer", if (self.mProjectionType == .Orthographic) true else false, imgui.ImGuiSelectableFlags_None, imgui.ImVec2{ .x = 50, .y = 50 })) {
            //scene_component.mLayerType = .OverlayLayer;
            //TODO: add a way to move the layer to the section where it belongs. maybe need some imgui event?
        }
    }

    //TODO: print all the scripts. scripts since they cant hold data they dont really have a render so just need to print they exist
    if (self.mScenelayer.HasComponent(SceneScriptComponent) == true) {
        var curr_id = self.mScenelayer.mSceneID;
        while (curr_id != AssetHandle.NullHandle) {
            const script_component = self.mScenelayer.mECSManagerSCRef.GetComponent(SceneScriptComponent, curr_id);
            const file_meta_data = try script_component.mScriptAssetHandle.GetAsset(FileMetaData);
            const script_name = std.fs.path.basename(file_meta_data.mRelPath);

            imgui.igText(script_name);

            curr_id = script_component.mNext;
        }
    }
    //TODO: print all the render layers. i suppose render layers will just just be 1 render layer per 1 shader program. same as scripts,
    //it is just external shader code so therefore i just need to print that it exists and thats it

    defer imgui.igEnd();
}
