//! Everything in a world that takes up space, in one tree per layer: one for the game layer in world units, one for
//! every overlay scene together in canvas units (the world's one screen space, see WorldManager.mOverlayScaleMode). Built
//! once a frame right after the end-of-frame commit, so the set of items can't change until the next one, and refit as
//! things move. Shared by whatever asks what is where: the renderer, physics' broad phase, picking.
//!
//! One flat item per thing a ray or a box can meet: a quad, each letter of a text, a merge (its root standing for all
//! its parts) and a collider. Each item carries its entity, its scene and which systems it is for (BVH.Mask), so a walk
//! passes over what isn't its own: a view over scenes it doesn't show, physics over what is only drawn.
const std = @import("std");
const Tracy = @import("Tracy.zig");
const WorldManager = @import("WorldManager.zig");
const BVH = @import("BVH.zig");
const Aabb = @import("../Math/Aabb.zig");
const SDFFunctions = @import("../Math/SDFFunctions.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;

const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");
const TextLayout = @import("../Renderer/TextLayout.zig");
const SDFCompiler = @import("../Renderer/SDFCompiler.zig");
const CollisionManager = @import("../Physics/CollisionManager.zig");

const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const LayerType = @import("../ECSComponents/Scene/SceneComponent.zig").LayerType;
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const ColliderComponent = EntityComponents.ColliderComponent;

const WorldBVH = @This();

/// How many scenes a world can have items in: a view says which it shows as one bit each (SceneBits)
pub const MAX_SCENES: usize = 64;

pub const ItemKind = enum(u8) {
    Quad,
    /// one letter of a text, what is drawn (BVH.Mask.RENDER)
    Glyph,
    /// a whole text, from its first line's ascender down to its last one's descender: what is clicked
    /// (BVH.Mask.PICK), so a click between two letters still lands on it
    Text,
    /// a merge's root, standing for every part of it
    Merge,
    Collider,
};

/// What one item of a tree stands for
pub const WorldItem = struct {
    Entity: Entity.Type,
    Kind: ItemKind,
    /// the item's scene, as its place in mScenes
    SceneSlot: u8,
    /// a glyph's placement in mGlyphs, or a text's measurement in mTexts, which a refit places again without laying the
    /// text out again. 0 for the rest
    Index: u32 = 0,
    /// where it was added in its layer, before the build reordered them: the order entities come in, which doesn't
    /// change as they move. What the renderer breaks a tie between two shapes at exactly the same depth by, so the tie
    /// doesn't flip from frame to frame as the tree's shape changes
    Order: u32 = 0,
    /// the entity whose mask cuts it when it is drawn (ShapeGeometry.MaskRegionAbove), found once for each entity at
    /// the build rather than for each of its letters every render. Entity.NullObject for none, and for colliders,
    /// which masks never cut
    MaskRegion: Entity.Type = Entity.NullObject,
};

/// One layer's tree. mItems[i] is what mBVHItems[i] stands for, both in the order the build left them, so a leaf's
/// items are one run of each
pub const LayerTree = struct {
    mItems: std.ArrayList(WorldItem) = .empty,
    mBVHItems: std.ArrayList(BVH.Item) = .empty,
    mNodes: std.ArrayList(BVH.Node) = .empty,

    fn Deinit(self: *LayerTree, engine_allocator: std.mem.Allocator) void {
        self.mItems.deinit(engine_allocator);
        self.mBVHItems.deinit(engine_allocator);
        self.mNodes.deinit(engine_allocator);
    }

    fn Clear(self: *LayerTree) void {
        self.mItems.clearRetainingCapacity();
        self.mBVHItems.clearRetainingCapacity();
        self.mNodes.clearRetainingCapacity();
    }

    pub fn Add(self: *LayerTree, engine_allocator: std.mem.Allocator, item: WorldItem, bounds: Aabb, mask: u4) !void {
        try self.mBVHItems.append(engine_allocator, .{ .Id = @intCast(self.mItems.items.len), .Bounds = bounds, .Mask = mask });
        try self.mItems.append(engine_allocator, item);
    }

    /// The tree over what was added, and the items put in its order
    pub fn Build(self: *LayerTree, engine_allocator: std.mem.Allocator, frame_allocator: std.mem.Allocator) !void {
        const zone = Tracy.ZoneInit("WorldBVH::LayerTree::Build", @src());
        defer zone.Deinit();
        zone.Value(self.mItems.items.len);

        try BVH.Build(engine_allocator, self.mBVHItems.items, &self.mNodes);

        const reorder_zone = Tracy.ZoneInit("WorldBVH::LayerTree::Reorder", @src());
        defer reorder_zone.Deinit();
        const added = try frame_allocator.dupe(WorldItem, self.mItems.items);
        for (self.mBVHItems.items, self.mItems.items, 0..) |*bvh_item, *item, i| {
            item.* = added[bvh_item.Id];
            item.Order = bvh_item.Id;
            bvh_item.Id = @intCast(i);
        }
    }

    pub fn Stats(self: LayerTree) BVH.TreeStats {
        return BVH.Stats(self.mNodes.items);
    }
};

mGame: LayerTree = .{},
mOverlay: LayerTree = .{},
/// every laid out letter, which glyph items point into
mGlyphs: std.ArrayList(TextLayout.GlyphPlacement) = .empty,
/// every text's measured size, which text items point into
mTexts: std.ArrayList(TextLayout.Metrics) = .empty,
/// the scenes items are in, each one's place here its SceneSlot
mScenes: std.ArrayList(Scene.Type) = .empty,

pub fn Deinit(self: *WorldBVH, engine_allocator: std.mem.Allocator) void {
    self.mGame.Deinit(engine_allocator);
    self.mOverlay.Deinit(engine_allocator);
    self.mGlyphs.deinit(engine_allocator);
    self.mTexts.deinit(engine_allocator);
    self.mScenes.deinit(engine_allocator);
}

/// Holds nothing, its memory kept: for when the entities it names are gone
pub fn Clear(self: *WorldBVH) void {
    self.mGame.Clear();
    self.mOverlay.Clear();
    self.mGlyphs.clearRetainingCapacity();
    self.mTexts.clearRetainingCapacity();
    self.mScenes.clearRetainingCapacity();
}

pub fn Tree(self: *WorldBVH, layer: LayerType) *LayerTree {
    return switch (layer) {
        .GameLayer => &self.mGame,
        .OverlayLayer => &self.mOverlay,
    };
}

/// One bit for each of `scenes` that has items here, in SceneSlot order: what a view passes to only see those
pub fn SceneBits(self: WorldBVH, scenes: []const Scene.Type) u64 {
    var bits: u64 = 0;
    for (self.mScenes.items, 0..) |scene_id, slot| {
        if (std.mem.indexOfScalar(Scene.Type, scenes, scene_id) != null) bits |= @as(u64, 1) << @intCast(slot);
    }
    return bits;
}

/// Every refit mask at once: what is drawn, clicked and collided
pub const ALL_ITEMS: u4 = BVH.Mask.RENDER | BVH.Mask.PICK | BVH.Mask.PHYSICS;

/// The axis lined up box around an oriented one
pub fn BoxBounds(box: ShapeGeometry.Box) Aabb {
    const axis_x, const axis_y, const axis_z = box.Rotation.Axes();
    return SDFFunctions.aabbBox(box.Center, axis_x, axis_y, axis_z, box.HalfExtents);
}

/// A collider's box grown by how far it can reach this substep (CollisionManager.SubstepReach), so any two the narrow
/// pass could pair overlap, and the broad pass finds them by overlap alone. In canvas units for an overlay one, or null
/// without a transform
pub fn ColliderBounds(entity: Entity) ?Aabb {
    const transform = entity.GetComponent(TransformComponent) orelse return null;
    const collider = entity.GetComponent(ColliderComponent) orelse return null;
    const shape: Aabb = switch (collider.mShape) {
        .Box => BoxBounds(ShapeGeometry.ColliderBox(transform, collider, null)),
        .Sphere => blk: {
            const sphere = ShapeGeometry.ColliderSphere(transform, collider, null);
            const reach = Vec3(f32){ .x = sphere.Radius, .y = sphere.Radius, .z = sphere.Radius };
            break :blk .{ .Min = sphere.Center.SubVec(reach), .Max = sphere.Center.AddVec(reach) };
        },
    };
    return shape.Grow(CollisionManager.SubstepReach(entity));
}

/// A merge's box, compiled the way the renderer and picking compile it, or null when it has no parts
pub fn MergeBounds(frame_allocator: std.mem.Allocator, root: Entity) !?Aabb {
    var programs: SDFCompiler.Programs = .{};
    const compiled = try SDFCompiler.Compile(frame_allocator, root, null, &programs);
    if (compiled.Parts.Count == 0) return null;
    return BoxBounds(ShapeGeometry.MergeBox(compiled));
}
