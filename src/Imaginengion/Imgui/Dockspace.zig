const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const Tracy = @import("../Core/Tracy.zig");
const EditorProgram = @import("../Programs/EditorProgram.zig");
const Dockspace = @This();

/// A rectangle in window coordinates (the mouse's), from its top left corner
pub const Rect = struct {
    Pos: @import("../Math/MathTypes.zig").Vec2(f32),
    Size: @import("../Math/MathTypes.zig").Vec2(f32),
};

/// The dockspace's id, from the last Begin
var gDockspaceID: imgui.ImGuiID = 0;
const Application = @import("../Core/Application.zig");
const EngineContext = @import("../Core/EngineContext.zig");

pub fn Begin() void {
    const zone = Tracy.ZoneInit("Dockspace::Begin", @src());
    defer zone.Deinit();

    const p_open = true;
    const my_null_ptr: ?*anyopaque = null;
    //the middle, where nothing is docked, shows the editor UI drawn underneath ImGui
    const dockspace_flags = imgui.ImGuiDockNodeFlags_PassthruCentralNode;

    var window_flags = imgui.ImGuiWindowFlags_MenuBar | imgui.ImGuiWindowFlags_NoDocking;

    const viewport = imgui.igGetMainViewport();
    imgui.igSetNextWindowPos(viewport.*.WorkPos, 0, .{ .x = 0, .y = 0 });
    imgui.igSetNextWindowSize(viewport.*.WorkSize, 0);
    imgui.igSetNextWindowViewport(viewport.*.ID);
    imgui.igPushStyleVar_Float(imgui.ImGuiStyleVar_WindowRounding, 0);
    imgui.igPushStyleVar_Float(imgui.ImGuiStyleVar_WindowBorderSize, 0);
    window_flags |= imgui.ImGuiWindowFlags_NoTitleBar | imgui.ImGuiWindowFlags_NoCollapse | imgui.ImGuiWindowFlags_NoResize | imgui.ImGuiWindowFlags_NoMove;
    window_flags |= imgui.ImGuiWindowFlags_NoBringToFrontOnFocus | imgui.ImGuiWindowFlags_NoNavFocus;
    window_flags |= imgui.ImGuiWindowFlags_NoBackground;

    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });

    _ = imgui.igBegin("EngineDockspace", @ptrCast(@constCast(&p_open)), window_flags);

    imgui.igPopStyleVar(1);
    imgui.igPopStyleVar(2);

    const dockspace_id = imgui.igGetID_Str("EngineDockspace");
    gDockspaceID = dockspace_id;
    _ = imgui.igDockSpace(dockspace_id, .{ .x = 0, .y = 0 }, dockspace_flags, @ptrCast(@alignCast(my_null_ptr)));
}

/// Where the middle of the dockspace is, the area the docked panels leave free, as of the last frame it was laid out.
/// Null before there has been a dockspace
pub fn CentralRect() ?Rect {
    if (gDockspaceID == 0) return null;
    const node: *const DockNodeHead = @ptrCast(@alignCast(imgui.igDockBuilderGetCentralNode(gDockspaceID) orelse return null));
    return .{ .Pos = .{ .x = node.Pos.x, .y = node.Pos.y }, .Size = .{ .x = node.Size.x, .y = node.Size.y } };
}

/// The start of ImGui's ImGuiDockNode (imgui_internal.h, mirrored in cimgui.h), as far as its Pos and Size. The whole
/// struct comes through translate-c as opaque, since it has bitfields further on; these leading fields are plain C, so
/// an extern struct of them is laid out exactly as C lays them out. Keep it in step with the vendored ImGui
const DockNodeHead = extern struct {
    ID: imgui.ImGuiID,
    SharedFlags: c_int,
    LocalFlags: c_int,
    LocalFlagsInWindows: c_int,
    MergedFlags: c_int,
    State: c_int,
    ParentNode: ?*anyopaque,
    ChildNodes: [2]?*anyopaque,
    Windows: extern struct { Size: c_int, Capacity: c_int, Data: ?*anyopaque },
    TabBar: ?*anyopaque,
    Pos: extern struct { x: f32, y: f32 },
    Size: extern struct { x: f32, y: f32 },
};

pub fn End() void {
    const zone = Tracy.ZoneInit("Dockspace::End", @src());
    defer zone.Deinit();
    imgui.igEnd();
}
