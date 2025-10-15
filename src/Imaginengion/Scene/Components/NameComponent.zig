const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const NameComponent = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == NameComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;

mName: std.ArrayList(u8) = .{},

mAllocator: std.mem.Allocator = undefined,

pub fn Deinit(self: *NameComponent) !void {
    self.mName.deinit(self.mAllocator);
}

pub fn GetName(self: NameComponent) []const u8 {
    _ = self;
    return "NameComponent";
}

pub fn GetInd(self: NameComponent) u32 {
    _ = self;
    return @intCast(Ind);
}
