const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const imgui = @import("../../Core/CImports.zig").imgui;
const AttribComponent = @This();

pub const ValueTypes = union(enum) {
    uint32: u32,
    int32: i32,
    float32: f32,
    bool: bool,

    pub const default: ValueTypes = .{ .uint32 = 0 };
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
    const Tag = std.meta.Tag(ValueTypes);
    const current_tag: Tag = self.mData;
    if (imgui.igBeginCombo("Type", @tagName(current_tag), 0)) {
        defer imgui.igEndCombo();
        inline for (std.meta.fields(Tag)) |field| {
            const tag_value: Tag = @enumFromInt(field.value);
            const selected = tag_value == current_tag;

            if (imgui.igSelectable_Bool(field.name.ptr, selected, 0, .{ .x = 0, .y = 0 })) {
                if (tag_value != current_tag) {
                    self.mData = switch (tag_value) {
                        .uint32 => .{ .uint32 = 0 },
                        .int32 => .{ .int32 = 0 },
                        .float32 => .{ .float32 = 0.0 },
                        .bool => .{ .bool = false },
                    };
                }
            }

            if (selected) imgui.igSetItemDefaultFocus();
        }
    }

    switch (self.mData) {
        .uint32 => |*v| {
            var temp: i32 = @intCast(v.*);
            if (imgui.igInputInt("Value", &temp, 1, 10, 0)) {
                if (temp >= 0) {
                    v.* = @intCast(temp);
                }
            }
        },
        .int32 => |*v| {
            _ = imgui.igInputInt("Value", v, 1, 10, 0);
        },
        .float32 => |*v| {
            _ = imgui.igInputFloat("Value", v, 0.1, 1.0, "%.3f", 0);
        },
        .bool => |*v| {
            _ = imgui.igCheckbox("Value", v);
        },
    }
}
