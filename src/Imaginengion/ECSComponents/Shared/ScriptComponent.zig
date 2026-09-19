const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ScriptComponent = @This();

const Assets = @import("../../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;
const FileMetaData = Assets.FileMetaData;

const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

const Entity = @import("../../GameObjects/Entity.zig");
const AssetType = @import("../../Assets/AssetManager.zig").AssetType;

const EngineContext = @import("../../Core/EngineContext.zig");

mParent: Entity.Type = Entity.NullEntity,
mFirst: Entity.Type = Entity.NullEntity,
mPrev: Entity.Type = Entity.NullEntity,
mNext: Entity.Type = Entity.NullEntity,

mScriptAssetHandle: AssetHandle = .uninit,

pub const Editable: bool = false;
pub const Name: []const u8 = "ScriptComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ScriptComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn Deinit(self: *ScriptComponent, _: *EngineContext) !void {
    self.mScriptAssetHandle.ReleaseAsset();
}

const Json = JsonUtils.JsonFields(ScriptComponent, .{ .Script = "mScriptAssetHandle" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;
