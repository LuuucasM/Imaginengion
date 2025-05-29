const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;

pub fn AllScriptPopupMenu() !void {
    if (imgui.igBeginMenu("All Scripts", true) == true) {
        defer imgui.igEndMenu();
        try EntityScriptPopupMenu();
        try SceneScriptPopupMenu();
    }
}

pub fn EntityScriptPopupMenu() !void {
    if (imgui.igBeginMenu("New Game Object Script", true) == true) {
        defer imgui.igEndMenu();
        if (imgui.igMenuItem_Bool("On Key Pressed Script", "", false, true) == true) {
            const new_script_event = ImguiEvent{
                .ET_NewScriptEvent = .{
                    .mScriptType = .OnInputPressed,
                },
            };
            try ImguiEventManager.Insert(new_script_event);
        }
        if (imgui.igMenuItem_Bool("On Update Input Script", "", false, true) == true) {
            const new_script_event = ImguiEvent{
                .ET_NewScriptEvent = .{
                    .mScriptType = .OnUpdateInput,
                },
            };
            try ImguiEventManager.Insert(new_script_event);
        }
    }
}

pub fn SceneScriptPopupMenu() !void {
    if (imgui.igBeginMenu("New Scene Script", true) == true) {
        defer imgui.igEndMenu();
        if (imgui.igMenuItem_Bool("On Scene Start Script", "", false, true) == true) {
            const new_script_event = ImguiEvent{
                .ET_NewScriptEvent = .{
                    .mScriptType = .OnSceneStart,
                },
            };
            try ImguiEventManager.Insert(new_script_event);
        }
    }
}
