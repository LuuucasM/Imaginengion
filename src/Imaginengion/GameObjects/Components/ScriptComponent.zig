const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ScriptComponent = @This();

const Assets = @import("../../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;

const AssetHandle = @import("../../Assets/AssetHandle.zig");

const EditorWindow = @import("../../Imgui/EditorWindow.zig");

const Entity = @import("../../GameObjects/Entity.zig");
const AssetType = @import("../../Assets/AssetManager.zig").AssetType;

mFirst: Entity.Type = Entity.NullEntity,
mPrev: Entity.Type = Entity.NullEntity,
mNext: Entity.Type = Entity.NullEntity,
mParent: Entity.Type = Entity.NullEntity,
mScriptAssetHandle: AssetHandle = .{ .mID = AssetHandle.NullHandle },

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

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ScriptComponent) {
            break :blk i;
        }
    }
};
