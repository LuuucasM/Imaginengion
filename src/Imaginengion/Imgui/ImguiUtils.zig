const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;

pub fn ScriptPopupMenu() !void {
    if (imgui.igBeginMenu("New Script", true) == true) {
        defer imgui.igEndMenu();
        if (imgui.igMenuItem_Bool("On Key Pressed Script", "", false, true) == true) {
            const new_script_event = ImguiEvent{
                .ET_NewScriptEvent = .{
                    .mScriptType = .OnKeyPressed,
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
