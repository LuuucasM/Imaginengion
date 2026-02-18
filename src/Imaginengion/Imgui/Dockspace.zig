const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const Tracy = @import("../Core/Tracy.zig");
const EditorProgram = @import("../Programs/EditorProgram.zig");
const Dockspace = @This();
const Application = @import("../Core/Application.zig");
const EngineContext = @import("../Core/EngineContext.zig");

pub fn Begin() void {
    const zone = Tracy.ZoneInit("Dockspace Begin", @src());
    defer zone.Deinit();

    const p_open = true;
    const my_null_ptr: ?*anyopaque = null;
    const dockspace_flags = imgui.ImGuiDockNodeFlags_None;

    var window_flags = imgui.ImGuiWindowFlags_MenuBar | imgui.ImGuiWindowFlags_NoDocking;

    const viewport = imgui.igGetMainViewport();
    imgui.igSetNextWindowPos(viewport.*.WorkPos, 0, .{ .x = 0, .y = 0 });
    imgui.igSetNextWindowSize(viewport.*.WorkSize, 0);
    imgui.igSetNextWindowViewport(viewport.*.ID);
    imgui.igPushStyleVar_Float(imgui.ImGuiStyleVar_WindowRounding, 0);
    imgui.igPushStyleVar_Float(imgui.ImGuiStyleVar_WindowBorderSize, 0);
    window_flags |= imgui.ImGuiWindowFlags_NoTitleBar | imgui.ImGuiWindowFlags_NoCollapse | imgui.ImGuiWindowFlags_NoResize | imgui.ImGuiWindowFlags_NoMove;
    window_flags |= imgui.ImGuiWindowFlags_NoBringToFrontOnFocus | imgui.ImGuiWindowFlags_NoNavFocus;

    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });

    _ = imgui.igBegin("EngineDockspace", @ptrCast(@constCast(&p_open)), window_flags);

    imgui.igPopStyleVar(1);
    imgui.igPopStyleVar(2);

    const dockspace_id = imgui.igGetID_Str("EngineDockspace");
    _ = imgui.igDockSpace(dockspace_id, .{ .x = 0, .y = 0 }, dockspace_flags, @ptrCast(@alignCast(my_null_ptr)));
}

pub fn End() void {
    const zone = Tracy.ZoneInit("Dockspace End", @src());
    defer zone.Deinit();
    imgui.igEnd();
}
