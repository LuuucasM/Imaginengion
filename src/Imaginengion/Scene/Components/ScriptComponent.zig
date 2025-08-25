const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const ScriptComponent = @This();

const Assets = @import("../../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;

const AssetHandle = @import("../../Assets/AssetHandle.zig");

const EditorWindow = @import("../../Imgui/EditorWindow.zig");

const SceneLayer = @import("../SceneLayer.zig");
const SceneType = @import("../SceneLayer.zig").Type;
const AssetType = @import("../../Assets/AssetManager.zig").AssetType;

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ScriptComponent) {
            break :blk i;
        }
    }
};

mFirst: SceneType = SceneLayer.NullScene,
mPrev: SceneType = SceneLayer.NullScene,
mNext: SceneType = SceneLayer.NullScene,
mParent: SceneType = SceneLayer.NullScene,
mScriptAssetHandle: AssetHandle = .{ .mID = AssetHandle.NullHandle },

pub fn Deinit(_: *ScriptComponent) !void {}

pub fn GetName(self: ScriptComponent) []const u8 {
    _ = self;
    return "ScriptComponent";
}

pub fn GetInd(self: ScriptComponent) u32 {
    _ = self;
    return @intCast(Ind);
}
