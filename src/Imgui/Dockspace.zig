const imgui = @import("../Core/CImports.zig").imgui;

pub fn Begin() void {
    const opt_fullscreen = true;
    const opt_padding = false;
    const p_open = true;
    const my_null_ptr: ?*anyopaque = null;
    var dockspace_flags = imgui.ImGuiDockNodeFlags_None;

    var window_flags = imgui.ImGuiWindowFlags_MenuBar | imgui.ImGuiWindowFlags_NoDocking;
    if (opt_fullscreen == true) {
        const viewport = imgui.igGetMainViewport();
        imgui.igSetNextWindowPos(viewport.*.WorkPos, 0, .{ .x = 0, .y = 0 });
        imgui.igSetNextWindowSize(viewport.*.WorkSize, 0);
        imgui.igSetNextWindowViewport(viewport.*.ID);
        imgui.igPushStyleVar_Float(imgui.ImGuiStyleVar_WindowRounding, 0);
        imgui.igPushStyleVar_Float(imgui.ImGuiStyleVar_WindowBorderSize, 0);
        window_flags |= imgui.ImGuiWindowFlags_NoTitleBar | imgui.ImGuiWindowFlags_NoCollapse | imgui.ImGuiWindowFlags_NoResize | imgui.ImGuiWindowFlags_NoMove;
        window_flags |= imgui.ImGuiWindowFlags_NoBringToFrontOnFocus | imgui.ImGuiWindowFlags_NoNavFocus;
    } else {
        dockspace_flags &= ~imgui.ImGuiDockNodeFlags_PassthruCentralNode;
    }

    if (dockspace_flags & imgui.ImGuiDockNodeFlags_PassthruCentralNode != 0) {
        window_flags |= imgui.ImGuiWindowFlags_NoBackground;
    }

    if (opt_padding == false) {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
    }
    _ = imgui.igBegin("Dockspace Demo", @ptrCast(@constCast(&p_open)), window_flags);
    if (opt_padding == false) {
        imgui.igPopStyleVar(1);
    }
    if (opt_fullscreen == true) {
        imgui.igPopStyleVar(2);
    }

    const dockspace_id = imgui.igGetID_Str("MyDockSpace");
    _ = imgui.igDockSpace(dockspace_id, .{ .x = 0, .y = 0 }, dockspace_flags, @ptrCast(@alignCast(my_null_ptr)));

    if (imgui.igBeginMenuBar() == true) {
        if (imgui.igBeginMenu("File", true) == true) {
            if (imgui.igMenuItem_Bool("New Project", "Ctrl+N", false, true) == true) {}
            if (imgui.igMenuItem_Bool("Open Project", "Ctrl+O", false, true) == true) {}
            if (imgui.igMenuItem_Bool("Save", "Ctrl+S", false, true) == true) {}
            if (imgui.igMenuItem_Bool("Save As...", "Ctrl+Shift+S", false, true) == true) {}
            if (imgui.igMenuItem_Bool("Exit", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {}
            imgui.igEndMenu();
        }
        imgui.igEndMenuBar();
    }
}
pub fn End() void {
    imgui.igEnd();
}
