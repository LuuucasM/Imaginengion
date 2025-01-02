const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiManager = @import("Imgui.zig");
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const EventManager = @import("../Events/EventManager.zig");
const Event = @import("../Events/Event.zig").Event;
const Dockspace = @This();
const Application = @import("../Core/Application.zig");

pub fn Begin() void {
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

pub fn OnImguiRender() !void {
    const my_null_ptr: ?*anyopaque = null;
    if (imgui.igBeginMenuBar() == true) {
        defer imgui.igEndMenuBar();
        if (imgui.igBeginMenu("File", true) == true) {
            defer imgui.igEndMenu();
            if (imgui.igBeginMenu("New Scene", true) == true) {
                defer imgui.igEndMenu();
                if (imgui.igMenuItem_Bool("New Game Scene", "", false, true) == true) {
                    const new_event = ImguiEvent{
                        .ET_NewSceneEvent = .{
                            .mLayerType = .GameLayer,
                        },
                    };
                    try ImguiManager.InsertEvent(new_event);
                }
                if (imgui.igMenuItem_Bool("New Overlay Scene", "", false, true) == true) {
                    const new_event = ImguiEvent{
                        .ET_NewSceneEvent = .{
                            .mLayerType = .OverlayLayer,
                        },
                    };
                    try ImguiManager.InsertEvent(new_event);
                }
            }
            if (imgui.igMenuItem_Bool("Open Scene", "", false, true) == true) {
                const path = try PlatformUtils.OpenFile(ImguiManager.EventAllocator(), ".imsc");
                const new_event = ImguiEvent{
                    .ET_OpenSceneEvent = .{
                        .Path = path,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
            if (imgui.igMenuItem_Bool("Save Scene", "", false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_SaveSceneEvent = .{},
                };
                try ImguiManager.InsertEvent(new_event);
            }
            if (imgui.igMenuItem_Bool("Save Scene As...", "", false, true) == true) {
                const path = try PlatformUtils.OpenFolder(ImguiManager.EventAllocator());
                const new_event = ImguiEvent{
                    .ET_SaveSceneAsEvent = .{
                        .Path = path,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
            imgui.igSeparator();
            if (imgui.igMenuItem_Bool("New Project", "", false, true) == true) {
                const path = try PlatformUtils.OpenFolder(ImguiManager.EventAllocator());
                const new_event = ImguiEvent{
                    .ET_NewProjectEvent = .{
                        .Path = path,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
            if (imgui.igMenuItem_Bool("Open Project", "", false, true) == true) {
                const path = try PlatformUtils.OpenFile(ImguiManager.EventAllocator(), ".imprj");
                const new_event = ImguiEvent{
                    .ET_OpenProjectEvent = .{ .Path = path },
                };
                try ImguiManager.InsertEvent(new_event);
            }
            imgui.igSeparator();
            if (imgui.igMenuItem_Bool("Exit", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = Event{
                    .ET_WindowClose = .{},
                };
                try EventManager.Insert(new_event);
            }
        }
        if (imgui.igBeginMenu("Window", true) == true) {
            defer imgui.igEndMenu();
            if (imgui.igMenuItem_Bool("Asset Handles", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .AssetHandles,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
            if (imgui.igMenuItem_Bool("Components", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .Components,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
            if (imgui.igMenuItem_Bool("Content Browser", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .ContentBrowser,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
            if (imgui.igMenuItem_Bool("Component/Script Editor", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .CSEditor,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
            if (imgui.igMenuItem_Bool("Scene", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .Scene,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
            if (imgui.igMenuItem_Bool("Scripts", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .Scripts,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
            if (imgui.igMenuItem_Bool("Stats", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .Stats,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
            if (imgui.igMenuItem_Bool("Viewport", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .Viewport,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
        }
    }
}

pub fn End() void {
    imgui.igEnd();
}
