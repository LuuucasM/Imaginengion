const EngineContext = @import("../../Core/EngineContext.zig");

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
