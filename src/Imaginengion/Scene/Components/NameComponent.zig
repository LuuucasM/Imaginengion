const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const NameComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == NameComponent) {
            break :blk i;
        }
    }
};

Name: std.ArrayList(u8) = undefined,

pub fn Deinit(self: *NameComponent) !void {
    self.Name.deinit();
}

pub fn GetEditorWindow(self: *NameComponent) EditorWindow {
    return EditorWindow.Init(self);
}

pub fn GetName(self: NameComponent) []const u8 {
    _ = self;
    return "NameComponent";
}

pub fn GetInd(self: NameComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn EditorRender(self: *NameComponent) !void {
    _ = imgui.igInputText("##Name", &self.Name, self.Name.len, imgui.ImGuiInputTextFlags_None, null, null);
}
