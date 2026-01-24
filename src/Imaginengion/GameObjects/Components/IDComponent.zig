const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const IDComponent = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;

pub const Category: ComponentCategory = .Unique;
pub const Editable: bool = true;
pub const Name: []const u8 = "IDComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == IDComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

ID: u64 = std.math.maxInt(u64),

pub fn Deinit(_: *IDComponent, _: *EngineContext) !void {}

pub fn EditorRender(self: *IDComponent, _: *EngineContext) !void {
    var buff: [140]u8 = undefined;
    const text = try std.fmt.bufPrintZ(&buff, "{d}\n", .{self.ID});
    _ = imgui.igInputText("ID", text.ptr, text.len, imgui.ImGuiInputTextFlags_ReadOnly, null, null);
}
