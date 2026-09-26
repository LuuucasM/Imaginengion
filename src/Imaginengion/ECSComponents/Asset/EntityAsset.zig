const std = @import("std");
const EntityAsset = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const Tracy = @import("../../Core/Tracy.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const TextSerializer = @import("../../Serializer/TextSerializer.zig");

pub const Name: []const u8 = "EntityAsset";

pub const empty: EntityAsset = .{
    .mEntity = .uninit,
};

/// The root of the loaded entity tree, which lives in EngineContext.mAssetWorld
mEntity: Entity = .uninit,

pub fn Init(self: *EntityAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, _: std.Io.File) !void {
    const zone = Tracy.ZoneInit("EntityAsset::Init", @src());
    defer zone.Deinit();
    zone.Text(rel_path);

    //blank, every component comes from the file
    const root = try engine_context.mAssetEntityScene.CreateEntity(engine_context, .{ .bAddUUID = false, .bAddName = false, .bAddTransform = false });
    errdefer Destroy(engine_context, root);

    //TextSerializer rather than Serializer.DeserializeECSObj: that one also records the object as the
    //file's owner in mFileObjects, which would take an asset handle to the very asset being loaded
    try TextSerializer.DeserializeECSObj(engine_context, root, abs_path);
    engine_context.mSerializer.ResolveUUIDs();

    self.mEntity = root;
}

pub fn Deinit(self: *EntityAsset, engine_context: *EngineContext) void {
    //at shutdown the asset world is emptied before the asset manager (see EngineContext.DeInit),
    //so the tree is already gone by the time this runs
    if (!self.mEntity.IsActive()) return;
    Destroy(engine_context, self.mEntity);
    self.mEntity = .uninit;
}

/// Loaded assets are shared through handles rather than copied, and a plain copy would point at the
/// same tree and destroy it twice
pub fn Clone(_: *const EntityAsset, _: *EngineContext) !EntityAsset {
    return error.AssetNotDuplicatable;
}

/// Takes the whole tree along, and its UUIDs out of the asset world, when the asset world's events are processed
fn Destroy(engine_context: *EngineContext, root: Entity) void {
    root.Delete(engine_context) catch |err| {
        std.log.err("EntityAsset failed to delete its entity tree: {s}", .{@errorName(err)});
    };
}
