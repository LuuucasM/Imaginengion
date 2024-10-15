const std = @import("std");
const Application = @import("../Core/Application.zig");
const Window = @import("../Windows/Window.zig");
const imgui = @import("../Core/CImports.zig").imgui;
const glfw = @import("../Core/CImports.zig").glfw;
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const Imgui = @This();

var ImguiManager: *Imgui = undefined;

_EngineAllocator: std.mem.Allocator,
_EventPool: std.heap.MemoryPool(ImguiEvent),

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    ImguiManager = try EngineAllocator.create(Imgui);
    ImguiManager.* = .{
        ._EngineAllocator = EngineAllocator,
        ._EventPool = std.heap.MemoryPool(ImguiEvent).init(std.heap.page_allocator),
    };
    _ = imgui.igCreateContext(null);
    const io: *imgui.ImGuiIO = imgui.igGetIO();
    io.ConfigFlags |= imgui.ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigFlags |= imgui.ImGuiConfigFlags_DockingEnable;
    io.ConfigFlags |= imgui.ImGuiConfigFlags_ViewportsEnable;

    const style = imgui.igGetStyle();

    imgui.igStyleColorsDark(style);
    //imgui.igStyleColorsLight(style);

    if (io.ConfigFlags & imgui.ImGuiConfigFlags_ViewportsEnable != 0) {
        style.*.WindowRounding = 0;
        style.*.Colors[2].w = 1;
    }

    SetDarkThemeColors(style);

    const window = Application.GetWindow().GetNativeWindow();
    _ = imgui.ImGui_ImplGlfw_InitForOpenGL(@ptrCast(window), true);
    _ = imgui.ImGui_ImplOpenGL3_Init("#version 460");
}
pub fn Deinit() void {
    imgui.ImGui_ImplOpenGL3_Shutdown();
    imgui.ImGui_ImplGlfw_Shutdown();
    imgui.igDestroyContext(null);
    ImguiManager._EventPool.deinit();
    ImguiManager._EngineAllocator.destroy(ImguiManager);
}
pub fn Begin() void {
    imgui.ImGui_ImplOpenGL3_NewFrame();
    imgui.ImGui_ImplGlfw_NewFrame();
    imgui.igNewFrame();
}
pub fn End() void {
    const my_null_ptr: ?*anyopaque = null;
    const io: *imgui.ImGuiIO = imgui.igGetIO();
    const window: *Window = @ptrCast(@alignCast(Application.GetWindow().GetNativeWindow()));

    io.DisplaySize = .{ .x = @floatFromInt(window.GetWidth()), .y = @floatFromInt(window.GetHeight()) };

    imgui.igRender();
    imgui.ImGui_ImplOpenGL3_RenderDrawData(imgui.igGetDrawData());
    if (io.ConfigFlags & imgui.ImGuiConfigFlags_ViewportsEnable != 0) {
        const backup_current_context: ?*glfw.struct_GLFWwindow = glfw.glfwGetCurrentContext();
        imgui.igUpdatePlatformWindows();
        imgui.igRenderPlatformWindowsDefault(@ptrCast(@alignCast(my_null_ptr)), @ptrCast(@alignCast(my_null_ptr)));
        glfw.glfwMakeContextCurrent(backup_current_context);
    }
}

pub fn InsertEvent(event: ImguiEvent) !void {
    const ptr = try ImguiManager._EventPool.create();
    ptr.* = event;
}

pub fn GetFirstEvent() ?*std.SinglyLinkedList(usize).Node {
    return ImguiManager._EventPool.arena.state.buffer_list.first;
}

pub fn ClearEvents() void {
    _ = ImguiManager._EventPool.reset(.free_all);
}

fn SetDarkThemeColors(style: *imgui.struct_ImGuiStyle) void {

    //background
    style.*.Colors[imgui.ImGuiCol_WindowBg] = .{ .x = 2.0 / 255.0, .y = 5.0 / 255.0, .z = 8.0 / 255.0, .w = 1.0 };

    //Headers
    style.*.Colors[imgui.ImGuiCol_Header] = .{ .x = 155 / 255, .y = 207 / 255, .z = 234 / 255, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_HeaderHovered] = .{ .x = 0.293, .y = 0.317, .z = 0.382, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_HeaderActive] = .{ .x = 0.235, .y = 0.254, .z = 0.306, .w = 1.0 };

    //Buttons
    style.*.Colors[imgui.ImGuiCol_Button] = .{ .x = 0.250, .y = 0.266, .z = 0.358, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_ButtonHovered] = .{ .x = 0.375, .y = 0.399, .z = 0.537, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_ButtonActive] = .{ .x = 0.312, .y = 0.322, .z = 0.447, .w = 1.0 };

    //Frame BG
    style.*.Colors[imgui.ImGuiCol_FrameBg] = .{ .x = 0.317, .y = 0.290, .z = 0.290, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_FrameBgHovered] = .{ .x = 0.475, .y = 0.435, .z = 0.435, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_FrameBgActive] = .{ .x = 0.396, .y = 0.362, .z = 0.362, .w = 1.0 };
    //tabs
    style.*.Colors[imgui.ImGuiCol_Tab] = .{ .x = 255 / 255, .y = 207 / 255, .z = 234 / 255, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_TabHovered] = .{ .x = 155 / 255, .y = 207 / 255, .z = 234 / 255, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_TabSelected] = .{ .x = 0.375, .y = 0.210, .z = 0.493, .w = 1.0 };

    //titles
    style.*.Colors[imgui.ImGuiCol_TitleBg] = .{ .x = 198.0 / 255.0, .y = 113.0 / 255.0, .z = 186.0 / 255.0, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_TitleBgActive] = .{ .x = 0.188, .y = 0.104, .z = 0.246, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_TitleBgCollapsed] = .{ .x = 0.8, .y = 0.3, .z = 0.3, .w = 1.0 };

    //resize
    style.*.Colors[imgui.ImGuiCol_ResizeGrip] = .{ .x = 0.8, .y = 0.3, .z = 0.3, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_ResizeGripHovered] = .{ .x = 0.303, .y = 0.333, .z = 0.340, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_ResizeGripActive] = .{ .x = 0.404, .y = 0.444, .z = 0.454, .w = 1.0 };
}
