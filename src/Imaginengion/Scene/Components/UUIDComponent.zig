const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const UUIDComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;

ID: u64 = std.math.maxInt(u64),

pub const Name: []const u8 = "UUIDComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == UUIDComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn Deinit(_: *UUIDComponent, _: *EngineContext) !void {}

pub fn EditorRender(self: *UUIDComponent, _: *EngineContext) !void {
    var buff: [140]u8 = undefined;
    const text = try std.fmt.bufPrintZ(&buff, "{d}\n", .{self.ID});
    _ = imgui.igInputText("ID", text.ptr, text.len, imgui.ImGuiInputTextFlags_ReadOnly, null, null);
}
