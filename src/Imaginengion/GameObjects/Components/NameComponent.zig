const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const NameComponent = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

pub const Category: ComponentCategory = .Unique;

pub const Editable: bool = true;

Name: [24]u8 = std.mem.zeroes([24]u8),

pub fn Deinit(_: *NameComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == NameComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
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
