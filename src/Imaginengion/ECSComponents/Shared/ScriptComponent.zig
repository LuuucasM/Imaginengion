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
/// The object each object variable wants, whether it is loaded or not (see ScriptValues). The variables themselves are in
/// the script's DLL, and are only handles, which can't hold it
mLinks: std.ArrayList(Link) = .empty,

pub const Link = struct {
    /// the variable's name, hashed: the name itself is in the script's DLL, which a new build replaces
    mNameHash: u64,
    mUUID: u64,
};

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
    self.mLinks.deinit(engine_context.EngineAllocator());
}

/// The UUID the variable called `name` wants, null if it wants none
pub fn GetLink(self: *const ScriptComponent, name: []const u8) ?u64 {
    const hash = std.hash.Fnv1a_64.hash(name);
    for (self.mLinks.items) |link| {
        if (link.mNameHash == hash) return link.mUUID;
    }
    return null;
}

pub fn SetLink(self: *ScriptComponent, engine_context: *EngineContext, name: []const u8, uuid: u64) !void {
    const hash = std.hash.Fnv1a_64.hash(name);
    for (self.mLinks.items) |*link| {
        if (link.mNameHash == hash) {
            link.mUUID = uuid;
            return;
        }
    }
    try self.mLinks.append(engine_context.EngineAllocator(), .{ .mNameHash = hash, .mUUID = uuid });
}

pub fn RemoveLink(self: *ScriptComponent, name: []const u8) void {
    const hash = std.hash.Fnv1a_64.hash(name);
    for (self.mLinks.items, 0..) |link, index| {
        if (link.mNameHash == hash) {
            _ = self.mLinks.swapRemove(index);
            return;
        }
    }
}

/// Wants what `from` wants, instead of what it wanted
pub fn CopyLinks(self: *ScriptComponent, engine_context: *EngineContext, from: *const ScriptComponent) !void {
    self.mLinks.clearRetainingCapacity();
    try self.mLinks.appendSlice(engine_context.EngineAllocator(), from.mLinks.items);
}

pub fn Clone(self: *const ScriptComponent, engine_context: *EngineContext) !ScriptComponent {
    var new_component = self.*;

    // the copy releases the script asset itself, so it needs its own reference
    new_component.mScriptAssetHandle.RetainAsset();
    errdefer new_component.mScriptAssetHandle.ReleaseAsset();

    // and its own list of what its variables want
    new_component.mLinks = try self.mLinks.clone(engine_context.EngineAllocator());
    errdefer new_component.mLinks.deinit(engine_context.EngineAllocator());

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
        try ScriptValues.Write(self, instance, jw);
    }
    try jw.endObject();
}

const Json = JsonUtils.JsonFields(ScriptComponent, .{ .Script = "mScriptAssetHandle" });
pub const jsonParse = Json.jsonParse;
