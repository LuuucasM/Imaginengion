const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ScriptComponent = @This();

const AssetHandle = @import("../../Assets/AssetHandle.zig");

mFirst: u32 = std.math.maxInt(u32),
mPrev: u32 = std.math.maxInt(u32),
mNext: u32 = std.math.maxInt(u32),
mParent: u32 = std.math.maxInt(u32),
mScriptHandle: AssetHandle = .{ .mID = std.math.maxInt(u32) },

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ScriptComponent) {
            break :blk i;
        }
    }
};
