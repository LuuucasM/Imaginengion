const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const EngineContext = @import("../../Core/EngineContext.zig");

const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

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
    /// Drawn by RenderUnion under the type picker
    pub fn ImguiRender(self: *ValueTypes) !void {
        switch (self.*) {
            .uint32 => _ = try ImguiManager.RenderScalerInput(&self.uint32, "Value", 1, 10),
            .int32 => _ = try ImguiManager.RenderIntInput(&self.int32, "Value", 1, 10),
            .float32 => _ = try ImguiManager.RenderFloatInput(&self.float32, "Value", 0.5, 5),
            .bool => try ImguiManager.RenderBool(&self.bool, "Value"),
        }
    }

    /// The value as a float, whatever its type: 1 or 0 for a bool
    pub fn AsFloat(self: ValueTypes) f64 {
        return switch (self) {
            .uint32 => |v| @floatFromInt(v),
            .int32 => |v| @floatFromInt(v),
            .float32 => |v| v,
            .bool => |v| if (v) 1 else 0,
        };
    }

    /// Sets the value from a float, keeping its type: rounded to the nearest whole number for the integer types (u32
    /// stopping at 0 and both at the ends of their range), and true for anything but 0 for a bool
    pub fn SetFromFloat(self: *ValueTypes, value: f64) void {
        switch (self.*) {
            .uint32 => |*v| v.* = @intFromFloat(std.math.clamp(@round(value), 0, std.math.maxInt(u32))),
            .int32 => |*v| v.* = @intFromFloat(std.math.clamp(@round(value), std.math.minInt(i32), std.math.maxInt(i32))),
            .float32 => |*v| v.* = @floatCast(value),
            .bool => |*v| v.* = value != 0,
        }
    }
};

mData: ValueTypes = .default,

pub const Editable: bool = true;
pub const Name: []const u8 = "AttribComponent";

pub fn Deinit(_: *AttribComponent, _: *EngineContext) void {}

pub fn UIRender(self: *AttribComponent, ui: *Inspector.Builder) !void {
    try ui.Union(&self.mData, "Value", .{});
}

pub fn EditorRender(self: *AttribComponent, _: *EngineContext) !void {
    try ImguiManager.RenderUnion(ValueTypes, &self.mData, "Type");
}

//the value is written as { "<type>": value }, which is how std.json handles a tagged union
const Json = JsonUtils.JsonFields(AttribComponent, .{ .Data = "mData" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;
