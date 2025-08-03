const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const SystemEventManager = @import("../Events/SystemEventManager.zig");
const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const Tracy = @import("../Core/Tracy.zig");
const Dockspace = @This();
const Application = @import("../Core/Application.zig");

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

pub fn OnImguiRender() !void {
    const zone = Tracy.ZoneInit("Dockspace OIR", @src());
    defer zone.Deinit();

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
                    try ImguiEventManager.Insert(new_event);
                }
                if (imgui.igMenuItem_Bool("New Overlay Scene", "", false, true) == true) {
                    const new_event = ImguiEvent{
                        .ET_NewSceneEvent = .{
                            .mLayerType = .OverlayLayer,
                        },
                    };
                    try ImguiEventManager.Insert(new_event);
                }
            }
            if (imgui.igMenuItem_Bool("Open Scene", "", false, true) == true) {
                const path = try PlatformUtils.OpenFile(ImguiEventManager.EventAllocator(), ".imsc");
                const new_event = ImguiEvent{
                    .ET_OpenSceneEvent = .{
                        .Path = path,
                    },
                };
                try ImguiEventManager.Insert(new_event);
            }
            if (imgui.igMenuItem_Bool("Save Scene", "", false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_SaveSceneEvent = .{},
                };
                try ImguiEventManager.Insert(new_event);
            }
            if (imgui.igMenuItem_Bool("Save Scene As...", "", false, true) == true) {
                const abs_path = try PlatformUtils.SaveFile(ImguiEventManager.EventAllocator(), ".imsc");
                const new_event = ImguiEvent{
                    .ET_SaveSceneAsEvent = .{
                        .AbsPath = abs_path,
                    },
                };
                try ImguiEventManager.Insert(new_event);
            }
            imgui.igSeparator();
            if (imgui.igMenuItem_Bool("Save Entity", "", false, true)) {
                try ImguiEventManager.Insert(ImguiEvent{
                    .ET_SaveEntityEvent = .{},
                });
            }
            if (imgui.igMenuItem_Bool("Save Entity As...", "", false, true)) {
                const path = try PlatformUtils.SaveFile(ImguiEventManager.EventAllocator(), ".imfab");
                try ImguiEventManager.Insert(ImguiEvent{
                    .ET_SaveEntityAsEvent = .{
                        .Path = path,
                    },
                });
            }
            imgui.igSeparator();
            if (imgui.igMenuItem_Bool("New Project", "", false, true) == true) {
                const path = try PlatformUtils.OpenFolder(ImguiEventManager.EventAllocator());
                const new_event = ImguiEvent{
                    .ET_NewProjectEvent = .{
                        .Path = path,
                    },
                };
                try ImguiEventManager.Insert(new_event);
            }
            if (imgui.igMenuItem_Bool("Open Project", "", false, true) == true) {
                const path = try PlatformUtils.OpenFile(ImguiEventManager.EventAllocator(), ".imprj");
                const new_event = ImguiEvent{
                    .ET_OpenProjectEvent = .{ .Path = path },
                };
                try ImguiEventManager.Insert(new_event);
            }
            imgui.igSeparator();
            if (imgui.igMenuItem_Bool("Exit", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = SystemEvent{
                    .ET_WindowClose = .{},
                };
                try SystemEventManager.Insert(new_event);
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
                try ImguiEventManager.Insert(new_event);
            }
            if (imgui.igMenuItem_Bool("Components", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .Components,
                    },
                };
                try ImguiEventManager.Insert(new_event);
            }
            if (imgui.igMenuItem_Bool("Content Browser", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .ContentBrowser,
                    },
                };
                try ImguiEventManager.Insert(new_event);
            }
            if (imgui.igMenuItem_Bool("Component/Script Editor", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .CSEditor,
                    },
                };
                try ImguiEventManager.Insert(new_event);
            }
            if (imgui.igMenuItem_Bool("Scene", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .Scene,
                    },
                };
                try ImguiEventManager.Insert(new_event);
            }
            if (imgui.igMenuItem_Bool("Scripts", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .Scripts,
                    },
                };
                try ImguiEventManager.Insert(new_event);
            }
            if (imgui.igMenuItem_Bool("Stats", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .Stats,
                    },
                };
                try ImguiEventManager.Insert(new_event);
            }
            if (imgui.igMenuItem_Bool("Viewport", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .Viewport,
                    },
                };
                try ImguiEventManager.Insert(new_event);
            }
        }
        if (imgui.igBeginMenu("Editor", true) == true) {
            defer imgui.igEndMenu();
            if (imgui.igMenuItem_Bool("Use Play Panel", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .PlayPanel,
                    },
                };
                try ImguiEventManager.Insert(new_event);
            }
        }
    }
}

pub fn End() void {
    const zone = Tracy.ZoneInit("Dockspace End", @src());
    defer zone.Deinit();
    imgui.igEnd();
}
