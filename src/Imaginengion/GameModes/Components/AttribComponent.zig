const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");

const ImguiManager = @import("../../Imgui/Imgui.zig");

const AttribComponent = @This();

pub const ValueEnum = enum {
    uint32,
    int32,
    float32,
    bool,
};

pub const ValueTypes = union(ValueEnum) {
    uint32: u32,
    int32: i32,
    float32: f32,
    bool: bool,
    pub const default: ValueTypes = .{ .uint32 = 0 };
    pub fn EditorRender(self: *ValueTypes) !void {
        switch (self.*) {
            .uint32 => ImguiManager.RenderScalerInput(&self.uint32, "Value", 1, 10),
            .int32 => ImguiManager.RenderIntInput(&self.int32, "Value", 1, 10),
            .float32 => ImguiManager.RenderFloatInput(&self.float32, "Value", 0.5, 5),
            .bool => ImguiManager.RenderBool(&self.bool, "Value"),
        }
    }
};

mData: ValueTypes = .default,

pub const Editable: bool = true;
pub const Name: []const u8 = "AttribComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == AttribComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn Deinit(_: *AttribComponent, _: *EngineContext) !void {}

pub fn EditorRender(self: *AttribComponent, _: *EngineContext) !void {
    ImguiManager.RenderUnion(ValueTypes, self.mData, "Type");
}
