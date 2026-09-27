const EngineContext = @import("../../Core/EngineContext.zig");

pub const StaticBodyTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "StaticBodyTag";

    pub fn Deinit(_: *StaticBodyTag, _: *EngineContext) void {}
};

pub const DynamicBodyTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "DynamicBodyTag";

    pub fn Deinit(_: *DynamicBodyTag, _: *EngineContext) void {}
};

/// Marks an entity whose layout needs working out again: something it or its tree is sized or placed by has
/// changed. The tag is the query: the layout pass only visits the trees that have one, and clears it.
/// It carries no data, so the sparse set stores no value array for it. Never saved: a loaded tree is laid out
/// when it is first seen
pub const LayoutDirtyTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "LayoutDirtyTag";

    pub fn Deinit(_: *LayoutDirtyTag, _: *EngineContext) void {}
};

/// Marks an entity folded away by a collapsed layout item: the item itself and everything under it. The tag is the
/// query: the renderer and picking leave tagged entities out (ShapeGeometry.GatherViewShapes), so they are neither
/// drawn nor clickable, and only the layout pass puts it on or takes it off. Never saved: a loaded tree works it
/// out again when it is laid out
pub const LayoutHiddenTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "LayoutHiddenTag";

    pub fn Deinit(_: *LayoutHiddenTag, _: *EngineContext) void {}
};
