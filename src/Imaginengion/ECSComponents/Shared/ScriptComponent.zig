const std = @import("std");
const ScriptComponent = @This();

const Assets = @import("../AComponents.zig");
const ScriptAsset = Assets.ScriptAsset;
const FileMetaData = Assets.FileMetaData;

const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

const Entity = @import("../../ECSObjects/Entity.zig");
const AssetType = @import("../../Assets/AManager.zig").AssetType;

const EngineContext = @import("../../Core/EngineContext.zig");

mParent: Entity.Type = Entity.NullEntity,
mFirst: Entity.Type = Entity.NullEntity,
mPrev: Entity.Type = Entity.NullEntity,
mNext: Entity.Type = Entity.NullEntity,

mScriptAssetHandle: AssetHandle = .uninit,

pub const Editable: bool = false;
pub const Name: []const u8 = "ScriptComponent";

pub fn Deinit(self: *ScriptComponent, _: *EngineContext) void {
    self.mScriptAssetHandle.ReleaseAsset();
}

pub fn Clone(self: *const ScriptComponent, _: *EngineContext) !ScriptComponent {
    var new_component = self.*;

    // the copy releases the script asset itself, so it needs its own reference
    new_component.mScriptAssetHandle.RetainAsset();

    return new_component;
}

const Json = JsonUtils.JsonFields(ScriptComponent, .{ .Script = "mScriptAssetHandle" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;
