const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const ObjectLink = @import("../../ECSObjects/ObjectLink.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const RefMap = @import("../../ECSObjects/ECSObject.zig").RefMap;
const OverlayComponent = @This();

pub const Name: []const u8 = "OverlayComponent";

pub const uninit: OverlayComponent = .{
    .mScene = .uninit,
};

/// One overlay scene this player sees, drawn on top of the game in the player's view and nobody else's.
/// A player that sees several has one on itself and one on each child player that holds another (see
/// Player.AddOverlay), so showing or hiding an overlay is adding or deleting a child.
mScene: Scene = .uninit,
/// The UUID mScene wants, see ObjectLink
mWantedUUID: ?u64 = null,

pub fn UIRender(self: *OverlayComponent, ui: *Inspector.Builder) !void {
    _ = try ui.SceneRef(&self.mScene, "Overlay Scene", .{ .OverlayOnly = true, .OnChange = OnRefEdited });
}

fn OnRefEdited(component: *anyopaque) void {
    const self: *OverlayComponent = @ptrCast(@alignCast(component));
    self.mWantedUUID = ObjectLink.WantedNow(self.mScene, self.mWantedUUID);
}

pub fn Deinit(_: *OverlayComponent, _: *EngineContext) void {}

/// See WorldManager.RelinkRefs
pub fn Relink(self: *OverlayComponent) void {
    ObjectLink.Relink(&self.mScene, self.mWantedUUID);
}

/// The overlay scene, or null if there is none: never set, deleted since, or not an overlay
pub fn GetScene(self: OverlayComponent) ?Scene {
    if (!self.mScene.IsActive()) return null;
    if (self.mScene.GetLayer() != .OverlayLayer) return null;
    return self.mScene;
}

pub fn jsonStringify(self: *const OverlayComponent, jw: anytype) !void {
    try jw.beginObject();

    //A copy spawned from a template has no UUID, so it is left out: whatever spawned it attaches it again
    if (ObjectLink.WantedNow(self.mScene, self.mWantedUUID)) |scene_uuid| {
        try jw.objectField("Scene");
        try jw.write(scene_uuid);
    }

    try jw.endObject();
}

pub fn jsonParse(scratch_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!OverlayComponent {
    const FileData = struct { Scene: ?u64 = null };
    const file_data = try std.json.innerParse(FileData, scratch_allocator, reader, options);

    const scene_uuid = file_data.Scene orelse return .{};
    const requester = JsonUtils.EngineContextFromAllocator(scratch_allocator).mSerializer.mCurrDeserialize.requester;
    std.debug.assert(requester == .Player);
    return .{ .mScene = ObjectLink.Waiting(Scene, requester.Player.mManager), .mWantedUUID = scene_uuid };
}

/// A copy of a player template shows nothing until it is given overlays: the scene is not part of the
/// template, so there is no copy of it to point at (see ECSObject.Core.Fill)
pub fn RemapRefs(self: *OverlayComponent, _: *const RefMap) void {
    self.mScene = .uninit;
}
