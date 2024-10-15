const std = @import("std");
const Event = @import("../Events/Event.zig").Event;
const EventManager = @import("../Events/EventManager.zig");
const InputManager = @import("../Inputs/Input.zig");
const Renderer = @import("../Renderer/Renderer.zig");

const ImGui = @import("../Imgui/Imgui.zig");
const Dockspace = @import("../Imgui/Dockspace.zig");
const AssetHandlePanel = @import("../Imgui/AssethandlePanel.zig");
const ComponentsPanel = @import("../Imgui/ComponentsPanel.zig");
const ContentBrowserPanel = @import("../Imgui/ContentBrowserPanel.zig");
const PropertiesPanel = @import("../Imgui/PropertiesPanel.zig");
const ScenePanel = @import("../Imgui/ScenePanel.zig");
const ScriptsPanel = @import("../Imgui/ScriptsPanel.zig");
const StatsPanel = @import("../Imgui/StatsPanel.zig");
const ToolbarPanel = @import("../Imgui/ToolbarPanel.zig");
const ViewportPanel = @import("../Imgui/ViewportPanel.zig");
const ImguiEvent = @import("../Imgui/ImguiEvent.zig").ImguiEvent;
const AssetManager = @import("../Assets/AssetManager.zig");


_AssetHandlePanel: AssetHandlePanel,
_ComponentsPanel: ComponentsPanel,
_ContentBrowserPanel: ContentBrowserPanel,
_PropertiesPanel: PropertiesPanel,
_ScenePanel: ScenePanel,
_ScriptsPanel: ScriptsPanel,
_StatsPanel: StatsPanel,
_ToolbarPanel: ToolbarPanel,
_ViewportPanel: ViewportPanel,
_PathGPA: std.heap.GeneralPurposeAllocator(.{}) = std.heap.GeneralPurposeAllocator(.{}){},
_ProjectDirectory: []const u8,
//_EditorCamera

const EditorProgram = @This();

pub fn Init(EngineAllocator: std.mem.Allocator) !EditorProgram {
    try ImGui.Init(EngineAllocator);

    return EditorProgram{
        ._ProjectDirectory = "",
        ._AssetHandlePanel = AssetHandlePanel.Init(),
        ._ComponentsPanel = ComponentsPanel.Init(),
        ._ContentBrowserPanel = try ContentBrowserPanel.Init(),
        ._PropertiesPanel = PropertiesPanel.Init(),
        ._ScenePanel = ScenePanel.Init(),
        ._ScriptsPanel = ScriptsPanel.Init(),
        ._StatsPanel = StatsPanel.Init(),
        ._ToolbarPanel = ToolbarPanel.Init(),
        ._ViewportPanel = ViewportPanel.Init(),
    };
}

pub fn Deinit(self: *EditorProgram) void {
    self._ContentBrowserPanel.Deinit();
    self._PathGPA.allocator().free(self._ProjectDirectory);
    _ = self._PathGPA.deinit();
    ImGui.Deinit();
}

pub fn OnUpdate(self: *EditorProgram, dt: f64) !void {
    //process asset manager
    try AssetManager.OnUpdate();

    //Process Inputs
    InputManager.PollInputEvents();
    EventManager.ProcessEvents(.EC_Input);

    //--Imgui begin--
    ImGui.Begin();
    Dockspace.Begin();

    try self._AssetHandlePanel.OnImguiRender();
    self._ScenePanel.OnImguiRender();
    try self._ContentBrowserPanel.OnImguiRender();
    self._ComponentsPanel.OnImguiRender();
    self._PropertiesPanel.OnImguiRender();
    self._ScriptsPanel.OnImguiRender();
    self._ToolbarPanel.OnImguiRender();
    try self._StatsPanel.OnImguiRender(dt);
    self._ViewportPanel.OnImguiRender();
    try Dockspace.OnImguiRender(self._PathGPA.allocator());

    try self.ProcessImguiEvents();
    ImGui.ClearEvents();

    Dockspace.End();
    ImGui.End();
    //--Imgui end--

    //swap buffers
    Renderer.SwapBuffers();

    //Process window events
    EventManager.ProcessEvents(.EC_Window);

    //end of frame resets
    EventManager.EventsReset();
}

pub fn OnEvent(self: EditorProgram, event: *Event) void {
    _ = self;
    _ = event;
}

pub fn ProcessImguiEvents(self: *EditorProgram) !void {
    var it = ImGui.GetFirstEvent();
    while (it) |node| {
        const object_bytes = @as([*]u8, @ptrCast(node)) + @sizeOf(std.SinglyLinkedList(usize).Node);
        const event: *ImguiEvent = @ptrCast(@alignCast(object_bytes));
        switch (event.*) {
            .ET_TogglePanelEvent => |e| {
                switch (e._PanelType) {
                    .AssetHandles => self._AssetHandlePanel.OnImguiEvent(event),
                    .Components => self._ComponentsPanel.OnImguiEvent(event),
                    .ContentBrowser => try self._ContentBrowserPanel.OnImguiEvent(event),
                    .Properties => self._PropertiesPanel.OnImguiEvent(event),
                    .Scene => self._ScenePanel.OnImguiEvent(event),
                    .Scripts => self._ScriptsPanel.OnImguiEvent(event),
                    .Stats => self._StatsPanel.OnImguiEvent(event),
                    else => @panic("This event has not been handled by this type of panel yet!\n"),
                }
            },
            .ET_NewProjectEvent => {
                if (self._ProjectDirectory.len != 0) {
                    self._PathGPA.allocator().free(self._ProjectDirectory);
                }
                self._ProjectDirectory = event.ET_NewProjectEvent._Path;
                AssetManager.UpdateProjectDirectory(event.ET_NewProjectEvent._Path);
                try self._ContentBrowserPanel.OnImguiEvent(event);
            },
            .ET_OpenProjectEvent => {
                if (self._ProjectDirectory.len != 0) {
                    self._PathGPA.allocator().free(self._ProjectDirectory);
                }
                self._ProjectDirectory = event.ET_OpenProjectEvent._Path;
                AssetManager.UpdateProjectDirectory(std.fs.path.dirname(event.ET_OpenProjectEvent._Path).?);
                try self._ContentBrowserPanel.OnImguiEvent(event);
            },
            else => @panic("This event has not been handled by editor program!\n"),
        }
        it = node.next;
    }
}
