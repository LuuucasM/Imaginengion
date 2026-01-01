const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const EngineContext = @import("../Core/EngineContext.zig");

pub fn AllScriptPopupMenu() !void {
    if (imgui.igBeginMenu("All Scripts", true) == true) {
        defer imgui.igEndMenu();
        try EntityScriptPopupMenu();
        try SceneScriptPopupMenu();
    }
}

pub fn EntityScriptPopupMenu(engine_context: EngineContext) !void {
    if (imgui.igBeginMenu("New Game Object Script", true) == true) {
        defer imgui.igEndMenu();
        if (imgui.igMenuItem_Bool("On Key Pressed Script", "", false, true) == true) {
            const new_script_event = ImguiEvent{
                .ET_NewScriptEvent = .{
                    .mScriptType = .OnInputPressed,
                },
            };
            try engine_context.mImguiEventManager.Insert(new_script_event);
        }
        if (imgui.igMenuItem_Bool("On Update Input Script", "", false, true) == true) {
            const new_script_event = ImguiEvent{
                .ET_NewScriptEvent = .{
                    .mScriptType = .OnUpdateInput,
                },
            };
            try engine_context.mImguiEventManager.Insert(new_script_event);
        }
    }
}

pub fn SceneScriptPopupMenu(engine_context: EngineContext) !void {
    if (imgui.igBeginMenu("New Scene Script", true) == true) {
        defer imgui.igEndMenu();
        if (imgui.igMenuItem_Bool("On Scene Start Script", "", false, true) == true) {
            const new_script_event = ImguiEvent{
                .ET_NewScriptEvent = .{
                    .mScriptType = .OnSceneStart,
                },
            };
            try engine_context.mImguiEventManager.Insert(new_script_event);
        }
    }
}
