const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const IDComponent = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

pub const Category: ComponentCategory = .Unique;

ID: u64 = std.math.maxInt(u64),

pub fn Deinit(_: *IDComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == IDComponent) {
            break :blk i;
        }
    }
};

pub fn GetName(self: IDComponent) []const u8 {
    _ = self;
    return "IDComponent";
}

pub fn GetInd(self: IDComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn EditorRender(self: *IDComponent) !void {
    var buff: [140]u8 = undefined;
    const text = try std.fmt.bufPrintZ(&buff, "{d}\n", .{self.ID});
    _ = imgui.igInputText("ID", text.ptr, text.len, imgui.ImGuiInputTextFlags_ReadOnly, null, null);
}
