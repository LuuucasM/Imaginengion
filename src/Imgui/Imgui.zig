const std = @import("std");
const Application = @import("../Core/Application.zig");
const Window = @import("../Windows/Window.zig");
const imgui = @import("../Core/CImports.zig").imgui;
const glfw = @import("../Core/CImports.zig").glfw;

pub fn Init() void {
    _ = imgui.igCreateContext(null);
    const io: *imgui.ImGuiIO = imgui.igGetIO();
    io.ConfigFlags |= imgui.ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigFlags |= imgui.ImGuiConfigFlags_DockingEnable;
    io.ConfigFlags |= imgui.ImGuiConfigFlags_ViewportsEnable;

    imgui.igStyleColorsDark(imgui.igGetStyle());
    SetDarkThemeColors();

    const style = imgui.igGetStyle();
    if (io.ConfigFlags & imgui.ImGuiConfigFlags_ViewportsEnable != 0) {
        style.*.WindowRounding = 0;
        style.*.Colors[2].w = 1;
    }
    const window = Application.GetNativeWindow();
    _ = imgui.ImGui_ImplGlfw_InitForOpenGL(@ptrCast(window), true);
    _ = imgui.ImGui_ImplOpenGL3_Init("#version 460");
}
pub fn Deinit() void {
    imgui.ImGui_ImplOpenGL3_Shutdown();
    imgui.ImGui_ImplGlfw_Shutdown();
    imgui.igDestroyContext(null);
}
pub fn Begin() void {
    imgui.ImGui_ImplOpenGL3_NewFrame();
    imgui.ImGui_ImplGlfw_NewFrame();
    imgui.igNewFrame();
}
pub fn End() void {
    const my_null_ptr: ?*anyopaque = null;
    const io: *imgui.ImGuiIO = imgui.igGetIO();
    const window: *Window = @ptrCast(@alignCast(Application.GetNativeWindow()));

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

fn SetDarkThemeColors() void {
    var colors = imgui.igGetStyle().*.Colors;

    //background
    colors[imgui.ImGuiCol_WindowBg] = .{ .x = 0.082, .y = 0.082, .z = 0.082, .w = 1.0 };

    //Headers
    colors[imgui.ImGuiCol_Header] = .{ .x = 0.176, .y = 0.190, .z = 0.229, .w = 1.0 };
    colors[imgui.ImGuiCol_HeaderHovered] = .{ .x = 0.293, .y = 0.317, .z = 0.382, .w = 1.0 };
    colors[imgui.ImGuiCol_HeaderActive] = .{ .x = 0.235, .y = 0.254, .z = 0.306, .w = 1.0 };

    //Buttons
    colors[imgui.ImGuiCol_Button] = .{ .x = 0.250, .y = 0.266, .z = 0.358, .w = 1.0 };
    colors[imgui.ImGuiCol_ButtonHovered] = .{ .x = 0.375, .y = 0.399, .z = 0.537, .w = 1.0 };
    colors[imgui.ImGuiCol_ButtonActive] = .{ .x = 0.312, .y = 0.322, .z = 0.447, .w = 1.0 };

    //Frame BG
    colors[imgui.ImGuiCol_FrameBg] = .{ .x = 0.317, .y = 0.290, .z = 0.290, .w = 1.0 };
    colors[imgui.ImGuiCol_FrameBgHovered] = .{ .x = 0.475, .y = 0.435, .z = 0.435, .w = 1.0 };
    colors[imgui.ImGuiCol_FrameBgActive] = .{ .x = 0.396, .y = 0.362, .z = 0.362, .w = 1.0 };
    //tabs
    colors[imgui.ImGuiCol_Tab] = .{ .x = 0.8, .y = 0.3, .z = 0.3, .w = 1.0 };
    colors[imgui.ImGuiCol_TabHovered] = .{ .x = 0.45, .y = 0.252, .z = 0.592, .w = 1.0 };
    colors[imgui.ImGuiCol_TabSelected] = .{ .x = 0.375, .y = 0.210, .z = 0.493, .w = 1.0 };

    //titles
    colors[imgui.ImGuiCol_TitleBg] = .{ .x = 0.8, .y = 0.3, .z = 0.3, .w = 1.0 };
    colors[imgui.ImGuiCol_TitleBgActive] = .{ .x = 0.188, .y = 0.104, .z = 0.246, .w = 1.0 };
    colors[imgui.ImGuiCol_TitleBgCollapsed] = .{ .x = 0.8, .y = 0.3, .z = 0.3, .w = 1.0 };

    //resize
    colors[imgui.ImGuiCol_ResizeGrip] = .{ .x = 0.8, .y = 0.3, .z = 0.3, .w = 1.0 };
    colors[imgui.ImGuiCol_ResizeGripHovered] = .{ .x = 0.303, .y = 0.333, .z = 0.340, .w = 1.0 };
    colors[imgui.ImGuiCol_ResizeGripActive] = .{ .x = 0.404, .y = 0.444, .z = 0.454, .w = 1.0 };
}
