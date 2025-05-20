const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const ScriptComponent = @This();

const Assets = @import("../../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;

const AssetHandle = @import("../../Assets/AssetHandle.zig");

const EditorWindow = @import("../../Imgui/EditorWindow.zig");

const SceneType = @import("../../Scene/SceneManager.zig").SceneType;
const AssetType = @import("../../Assets/AssetManager.zig").AssetType;

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ScriptComponent) {
            break :blk i;
        }
    }
};

mFirst: SceneType = std.math.maxInt(SceneType),
mPrev: SceneType = std.math.maxInt(SceneType),
mNext: SceneType = std.math.maxInt(SceneType),
mParent: SceneType = std.math.maxInt(SceneType),
mScriptAssetHandle: AssetHandle = .{ .mID = std.math.maxInt(AssetType) },

pub fn Deinit(_: *ScriptComponent) !void {}

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
    const script = try self.mScriptHandle.GetAsset(ScriptAsset);
    try script.EditorRender();
}
