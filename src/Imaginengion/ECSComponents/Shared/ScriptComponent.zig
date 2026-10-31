const std = @import("std");
const ScriptComponent = @This();

const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const ScriptValues = @import("../../Scripts/ScriptValues.zig");

const EngineContext = @import("../../Core/EngineContext.zig");

//the owning object is the ECS ChildComponent's mParent: scripts are made with CreateChild(.Script)
mScriptAssetHandle: AssetHandle = .uninit,
/// This script child's variables, kept by the script's DLL under this id (see ScriptAsset.NewInstance). Null until the
/// script has loaded once; after that it stays, even while the script doesn't build (the last build keeps running)
mInstance: ?u32 = null,

pub const Editable: bool = false;
pub const Name: []const u8 = "ScriptComponent";

pub fn Deinit(self: *ScriptComponent, engine_context: *EngineContext) void {
    //the asset is loaded while there is an instance: this component holds a reference to it, and a script is swapped in
    //place rather than unloaded when its file changes
    if (ScriptValues.InstanceOf(self)) |instance| ScriptValues.ReleaseRefs(instance);
    if (self.mInstance) |id| {
        if (ScriptValues.AssetOf(self)) |asset| asset.FreeInstance(engine_context, id);
    }
    self.mInstance = null;
    self.mScriptAssetHandle.ReleaseAsset();
}

pub fn Clone(self: *const ScriptComponent, engine_context: *EngineContext) !ScriptComponent {
    var new_component = self.*;

    // the copy releases the script asset itself, so it needs its own reference
    new_component.mScriptAssetHandle.RetainAsset();
    errdefer new_component.mScriptAssetHandle.ReleaseAsset();

    // and its own variables, starting as these are
    new_component.mInstance = null;
    if (self.mInstance) |id| {
        if (ScriptValues.AssetOf(self)) |asset| new_component.mInstance = try asset.NewInstance(engine_context, id);
    }
    //the variables came across byte for byte, so each file ref needs its own reference
    if (ScriptValues.InstanceOf(&new_component)) |instance| ScriptValues.RetainRefs(instance);

    return new_component;
}

/// The script, and its variables by name (see ScriptValues.Write). Read back by TextSerializer.DeserializeScripts, which
/// has to add the script before its variables can be set
pub fn jsonStringify(self: *const ScriptComponent, jw: anytype) !void {
    try jw.beginObject();
    try jw.objectField("Script");
    try jw.write(self.mScriptAssetHandle);
    if (ScriptValues.InstanceOf(self)) |instance| {
        try jw.objectField("Values");
        try ScriptValues.Write(instance.mInfo, instance.mData, jw);
    }
    try jw.endObject();
}

const Json = JsonUtils.JsonFields(ScriptComponent, .{ .Script = "mScriptAssetHandle" });
pub const jsonParse = Json.jsonParse;
