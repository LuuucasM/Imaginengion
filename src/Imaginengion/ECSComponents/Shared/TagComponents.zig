const EngineContext = @import("../../Core/EngineContext.zig");
const Scene = @import("../../ECSObjects/Scene.zig");

/// Marks an entity whose local transform changed since the last transform pass.
///
/// The tag is the query itself: PhysicsManager.UpdateWorldTransforms asks for
/// `.{ .Component = TransformDirtyComponent }` and walks only those subtrees, instead of
/// rebuilding every root of the hierarchy every substep. It carries no data, so the sparse
/// set stores no value array for it.
///
/// Only Entity's transform setters add it and only UpdateWorldTransforms clears it, which is
/// why TransformComponent's local fields are private: a write that skipped the setter would
/// leave the entity untagged and its world transform stale.
pub const TransformDirtyTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "TransformDirtyTag";

    pub fn Deinit(_: *TransformDirtyTag, _: *EngineContext) void {}
};

pub const ShouldRenderTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "ShouldRenderTag";

    pub fn Deinit(_: *ShouldRenderTag, _: *EngineContext) void {}
};

/// Which layer a scene is drawn in. Game layer scenes are the world everyone sees, overlay scenes are
/// drawn on top, in front of the camera (see OverlayCanvas).
pub const LayerType = enum(u1) {
    GameLayer = 0,
    OverlayLayer = 1,
};

/// A scene's layer, and the layer of every entity in it. The tag is the query: the renderer and
/// picking ask for game shapes with `And{ shapes, GameLayerTag }` and never visit an overlay
/// entity to find out it isn't one.
///
/// On a scene it is the saved source of the layer, and getting it is what gives a loaded or spawned
/// scene its slot in the scene stack (PostParse). An entity's is never saved: Scene.CreateEntity and
/// Entity.CreateChild give it the one its scene has, and a scene's layer never changes.
pub const GameLayerTag = LayerTagT(.GameLayer);
pub const OverlayLayerTag = LayerTagT(.OverlayLayer);

/// The tag type for `layer`
pub fn LayerTag(comptime layer: LayerType) type {
    return switch (layer) {
        .GameLayer => GameLayerTag,
        .OverlayLayer => OverlayLayerTag,
    };
}

fn LayerTagT(comptime layer: LayerType) type {
    return struct {
        const Self = @This();
        pub const Layer: LayerType = layer;
        pub const Editable: bool = false;
        pub const Name: []const u8 = switch (layer) {
            .GameLayer => "GameLayerTag",
            .OverlayLayer => "OverlayLayerTag",
        };

        pub fn Deinit(_: *Self, _: *EngineContext) void {}

        /// A scene read from a file or copied from a template is slotted into the scene stack here,
        /// once its layer is known, the same as SManager.CreateScene does for a new one
        pub fn PostParse(_: *Self, engine_context: *EngineContext, owner: anytype) !void {
            if (@TypeOf(owner) == Scene) try owner.mManager.mSManager.InsertScene(engine_context, owner);
        }
    };
}
