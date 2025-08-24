const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const NameComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

Name: [24]u8 = std.mem.zeroes([24]u8),

pub fn Deinit(_: *NameComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == NameComponent) {
            break :blk i;
        }
    }
};

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
