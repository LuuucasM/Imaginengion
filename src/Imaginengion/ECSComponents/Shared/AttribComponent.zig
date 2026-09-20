const std = @import("std");
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
            .uint32 => try ImguiManager.RenderScalerInput(&self.uint32, "Value", 1, 10),
            .int32 => try ImguiManager.RenderIntInput(&self.int32, "Value", 1, 10),
            .float32 => try ImguiManager.RenderFloatInput(&self.float32, "Value", 0.5, 5),
            .bool => try ImguiManager.RenderBool(&self.bool, "Value"),
        }
    }
};

mData: ValueTypes = .default,

pub const Editable: bool = true;
pub const Name: []const u8 = "AttribComponent";

pub fn Deinit(_: *AttribComponent, _: *EngineContext) void {}

pub fn ImguiRender(self: *AttribComponent, _: *EngineContext) !void {
    try ImguiManager.RenderUnion(ValueTypes, &self.mData, "Type");
}
