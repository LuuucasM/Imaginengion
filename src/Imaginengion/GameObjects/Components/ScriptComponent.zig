const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ScriptComponent = @This();

const Assets = @import("../../Assets/Assets.zig");
const Script = Assets.Script;

const AssetHandle = @import("../../Assets/AssetHandle.zig");

const EditorWindow = @import("../../Imgui/EditorWindow.zig");

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

pub fn GetEditorWindow(self: *ScriptComponent) EditorWindow {
    return EditorWindow.Init(self);
}

pub fn GetName(self: ScriptComponent) []const u8 {
    _ = self;
    return "ScriptComponent";
}

pub fn GetInd(self: ScriptComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn EditorRender(self: *ScriptComponent) !void {
    self.mScriptHandle.GetAsset(Script).EditorRender();
}
