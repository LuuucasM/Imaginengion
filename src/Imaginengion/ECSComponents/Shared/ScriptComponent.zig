const std = @import("std");
const ScriptComponent = @This();

const Assets = @import("../AComponents.zig");
const ScriptAsset = Assets.ScriptAsset;
const FileMetaData = Assets.FileMetaData;

const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

const AssetType = @import("../../ECSManagers/AManager.zig").AssetType;

const EngineContext = @import("../../Core/EngineContext.zig");

//the owning object is the ECS ChildComponent's mParent: scripts are made with CreateChild(.Script)
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
