const std = @import("std");
const builtin = @import("builtin");
const AssetsList = @import("../Assets.zig").AssetsList;
const ScriptAsset = @This();

const EntityComponents = @import("../../GameObjects/Components.zig");
const EntityInputPressedScript = EntityComponents.OnInputPressedScript;
const EntityOnUpdateScript = EntityComponents.OnUpdateScript;

const SceneComponents = @import("../../Scene/SceneComponents.zig");
const SceneSceneStartScript = SceneComponents.OnSceneStartScript;
const SceneOnUpdateScript = SceneComponents.OnUpdateScript;
const SceneInputPressedScript = SceneComponents.InputPressedScript;

const EngineContext = @import("../../Core/EngineContext.zig");

pub const ScriptType = enum(u8) {
    //Game object scripts
    EntityInputPressed,
    EntityOnUpdate,

    //Scene Scripts
    SceneSceneStart,
    SceneInputPressed,
    SceneOnUpdate,
};

const Impl = switch (builtin.os.tag) {
    .windows => @import("ScriptAssets/WindowsScriptAsset.zig"),
    else => @import("ScriptAssets/OtherScriptAsset.zig"),
};

pub const Name: []const u8 = "ScriptAsset";
pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == ScriptAsset) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

_Impl: Impl = .{},

pub fn Init(self: *ScriptAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, asset_file: std.fs.File) !void {
    try self._Impl.Init(engine_context, abs_path, rel_path, asset_file);
}

pub fn Deinit(self: *ScriptAsset, engine_context: *EngineContext) !void {
    try self._Impl.Deinit(engine_context);
}

pub fn Run(self: *ScriptAsset, comptime script_type: type, args: anytype) bool {
    return self._Impl.Run(script_type, args);
}

pub fn EditorRender(self: *ScriptAsset) !void {
    self._Impl.EditorRender();
}
