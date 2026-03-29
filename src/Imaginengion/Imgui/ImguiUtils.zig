const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const Entity = @import("../GameObjects/Entity.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const AudioComponent = EntityComponents.AudioComponent;
const SceneComponents = @import("../Scene/SceneComponents.zig");

pub fn NewAllScriptsPopup(engine_context: *EngineContext) !void {
    if (imgui.igBeginMenu("All Scripts", true) == true) {
        defer imgui.igEndMenu();
        try NewEntityScriptPopup(engine_context);
        try NewSceneScriptPopup(engine_context);
    }
}

pub fn NewEntityComponentPopup(engine_context: *EngineContext, entity: Entity) !void {
    inline for (EntityComponents.ComponentPanelList) |component_type| {
        if (!entity.HasComponent(component_type)) {
            if (imgui.igMenuItem_Bool(component_type.Name.ptr, "", false, true)) {
                defer imgui.igCloseCurrentPopup();

                if (component_type == QuadComponent) {
                    const new_quad_component = QuadComponent{ .mTexture = .{ .mAssetManager = &engine_context.mAssetManager } };
                    _ = try entity.AddComponent(engine_context.EngineAllocator(), new_quad_component);
                } else if (component_type == TextComponent) {
                    const new_text_component = TextComponent{
                        .mTextAssetHandle = .{ .mAssetManager = &engine_context.mAssetManager },
                        .mTexHandle = .{ .mAssetManager = &engine_context.mAssetManager },
                    };
                    _ = try entity.AddComponent(engine_context.EngineAllocator(), new_text_component);
                } else if (component_type == AudioComponent) {
                    const new_audio_component = AudioComponent{ .mAudioAsset = .{ .mAssetManager = &engine_context.mAssetManager } };
                    _ = try entity.AddComponent(engine_context.EngineAllocator(), new_audio_component);
                } else {
                    _ = try entity.AddComponent(engine_context.EngineAllocator(), component_type{});
                }
            }
        }
    }
}

pub fn NewSceneComponentPopup(_: *EngineContext, scene_layer: SceneLayer) !void {
    inline for (SceneComponents.PanelList) |component_type| {
        if (!scene_layer.HasComponent(component_type)) {
            if (imgui.igMenuItem_Bool(component_type.Name.ptr, "", false, true)) {
                defer imgui.igCloseCurrentPopup();
                _ = try scene_layer.AddComponent(component_type{});
            }
        }
    }
}

pub fn NewEntityScriptPopup(engine_context: *EngineContext) !void {
    if (imgui.igBeginMenu("New Entity Script", true) == true) {
        defer imgui.igEndMenu();

        inline for (EntityComponents.ScriptsList) |script_type| {
            if (imgui.igMenuItem_Bool(script_type.Name.ptr, "", false, true)) {
                try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .RenderEnd, .{ .NewScriptEvent = .{ .mScriptType = script_type.Scripttype } });
            }
        }
    }
}

pub fn NewSceneScriptPopup(engine_context: *EngineContext) !void {
    if (imgui.igBeginMenu("New Scene Script", true) == true) {
        defer imgui.igEndMenu();

        inline for (SceneComponents.ScriptsList) |script_type| {
            if (imgui.igMenuItem_Bool(script_type.Name.ptr, "", false, true)) {
                try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .RenderEnd, .{ .NewScriptEvent = .{ .mScriptType = script_type.Scripttype } });
            }
        }
    }
}
