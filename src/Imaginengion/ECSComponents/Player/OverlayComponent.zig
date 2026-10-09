const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const SceneUUIDComponent = @import("../SComponents.zig").UUIDComponent;
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Serializer = @import("../../Serializer/Serializer.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const RefMap = @import("../../ECSObjects/ECSObject.zig").RefMap;
const OverlayComponent = @This();

pub const Name: []const u8 = "OverlayComponent";

/// One overlay scene this player sees, drawn on top of the game in the player's view and nobody else's.
/// A player that sees several has one on itself and one on each child player that holds another (see
/// Player.AddOverlay), so showing or hiding an overlay is adding or deleting a child.
mScene: Scene = .uninit,

/// Shown only, until there is something in the editor's own UI to drag a scene from
pub fn UIRender(self: *OverlayComponent, ui: *Inspector.Builder) !void {
    try ui.SceneName(&self.mScene, "Overlay Scene");
}

pub fn Deinit(_: *OverlayComponent, _: *EngineContext) void {}

/// The overlay scene, or null if there is none: never set, deleted since, or not an overlay
pub fn GetScene(self: OverlayComponent) ?Scene {
    if (!self.mScene.IsActive()) return null;
    if (self.mScene.GetLayer() != .OverlayLayer) return null;
    return self.mScene;
}

pub fn jsonStringify(self: *const OverlayComponent, jw: anytype) !void {
    try jw.beginObject();

    //scene references are saved as the scene's UUID and turned back into a scene once it is loaded. A copy
    //spawned from a template has no UUID, so it is left out: whatever spawned it attaches it again
    if (self.mScene.IsActive() and self.mScene.HasComponent(SceneUUIDComponent)) {
        try jw.objectField("Scene");
        try jw.write(self.mScene.GetUUID());
    }

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!OverlayComponent {
    const FileData = struct { Scene: ?u64 = null };
    const file_data = try std.json.innerParse(FileData, frame_allocator, reader, options);

    if (file_data.Scene) |scene_uuid| {
        const engine_context = JsonUtils.EngineContextFromAllocator(frame_allocator);
        const serializer = &engine_context.mSerializer;
        std.debug.assert(serializer.mCurrDeserialize.requester == .Player);
        try serializer.AddResolveReq(engine_context.EngineAllocator(), .{
            .Requester = serializer.mCurrDeserialize.requester,
            .UUID = scene_uuid,
            .Resolve = ResolveSceneRef,
        });
    }

    return OverlayComponent{};
}

/// A copy of a player template shows nothing until it is given overlays: the scene is not part of the
/// template, so there is no copy of it to point at (see ECSObject.Core.Fill)
pub fn RemapRefs(self: *OverlayComponent, _: *const RefMap) void {
    self.mScene = .uninit;
}

fn ResolveSceneRef(requester: Serializer.Requester, scene_uuid: u64) bool {
    const player = requester.Player;
    const scene = player.mManager.GetObjectByUUID(Scene, scene_uuid) orelse return false;
    //the component may have been removed since the request was made, nothing left to resolve
    const overlay = player.GetComponent(OverlayComponent) orelse return true;
    overlay.mScene = scene;
    return true;
}
