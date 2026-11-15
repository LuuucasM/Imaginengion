//! Everything in a world that takes up space, in one tree per layer: one for the game layer in world units, one for
//! every overlay scene together in canvas units (the world's one screen space, see WorldManager.mOverlayScaleMode). Built
//! once a frame right after the end-of-frame commit, so the set of items can't change until the next one, and refit as
//! things move. Shared by whatever asks what is where: the renderer, physics' broad phase, picking.
//!
//! One flat item per thing a ray or a box can meet: a quad, a text, a merge (its root standing for all its parts) and a
//! collider. A text is one item however many letters it has: its letters are in a small tree of its own, in its own
//! layout space (TextEntry), which only its layout changes. Where the text is, how it is turned or stretched never does,
//! so moving it refits one box, and the renderer walks into its letter tree from the text's item (like a mesh's own
//! tree under an object in a bigger engine's world tree). Each item carries its entity, its scene and which systems it is for (BVH.Mask), so a walk
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
const TextComponent = EntityComponents.TextComponent;

const WorldBVH = @This();

/// How many scenes a world can have items in: a view says which it shows as one bit each (SceneBits)
pub const MAX_SCENES: usize = 64;

pub const ItemKind = enum(u8) {
    Quad,
    /// a whole text: drawn (BVH.Mask.RENDER) by its letters, which are in its own letter tree (TextEntry), and clicked
    /// (BVH.Mask.PICK) anywhere from its first line's ascender down to its last one's descender, so a click between two
    /// letters still lands on it. Its box is around both (TextBounds)
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
    /// a text's TextEntry in mTexts, which a refit places again without laying the text out again. 0 for the rest
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

/// One laid out text: its measured size, its letters and the tree over them (BVH.BuildInOrder), all in the text's own
/// layout space (LetterBounds), before where it is placed, how it is turned or how it is stretched. The tree is its own:
/// its root is its first node, its nodes' children and Skips count from there, and its leaves' items are its letters,
/// counting from its first one. A text whose letters are all cut off has none, and no tree
pub const TextEntry = struct {
    Metrics: TextLayout.Metrics,
    /// its letters, a run of mGlyphs
    FirstGlyph: u32 = 0,
    GlyphCount: u32 = 0,
    /// its letter tree, a run of mLetterNodes
    FirstNode: u32 = 0,
    NodeCount: u32 = 0,
};

/// One layer's tree. mItems[i] is what mBVHItems[i] stands for, both in the order the build left them, so a leaf's
/// items are one run of each
pub const LayerTree = struct {
    mItems: std.ArrayList(WorldItem) = .empty,
    mBVHItems: std.ArrayList(BVH.Item) = .empty,
    mNodes: std.ArrayList(BVH.Node) = .empty,

    fn Deinit(self: *LayerTree, keep_allocator: std.mem.Allocator) void {
        self.mItems.deinit(keep_allocator);
        self.mBVHItems.deinit(keep_allocator);
        self.mNodes.deinit(keep_allocator);
    }

    fn Clear(self: *LayerTree) void {
        self.mItems.clearRetainingCapacity();
        self.mBVHItems.clearRetainingCapacity();
        self.mNodes.clearRetainingCapacity();
    }

    pub fn Add(self: *LayerTree, keep_allocator: std.mem.Allocator, item: WorldItem, bounds: Aabb, mask: u4) !void {
        try self.mBVHItems.append(keep_allocator, .{ .Id = @intCast(self.mItems.items.len), .Bounds = bounds, .Mask = mask });
        try self.mItems.append(keep_allocator, item);
    }

    /// The tree over what was added, and the items put in its order
    pub fn Build(self: *LayerTree, keep_allocator: std.mem.Allocator, scratch_allocator: std.mem.Allocator) !void {
        const zone = Tracy.ZoneInit("WorldBVH::LayerTree::Build", @src());
        defer zone.Deinit();
        zone.Value(self.mItems.items.len);

        try BVH.Build(keep_allocator, self.mBVHItems.items, &self.mNodes);

        const reorder_zone = Tracy.ZoneInit("WorldBVH::LayerTree::Reorder", @src());
        defer reorder_zone.Deinit();
        const added = try scratch_allocator.dupe(WorldItem, self.mItems.items);
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
/// every laid out letter, each text's a run of them (TextEntry)
mGlyphs: std.ArrayList(TextLayout.GlyphPlacement) = .empty,
/// every text's measured size and letter tree, which text items point into (WorldItem.Index)
mTexts: std.ArrayList(TextEntry) = .empty,
/// every text's letter tree, one run of nodes each (TextEntry.FirstNode)
mLetterNodes: std.ArrayList(BVH.Node) = .empty,
/// the scenes items are in, each one's place here its SceneSlot
mScenes: std.ArrayList(Scene.Type) = .empty,

pub fn Deinit(self: *WorldBVH, keep_allocator: std.mem.Allocator) void {
    self.mGame.Deinit(keep_allocator);
    self.mOverlay.Deinit(keep_allocator);
    self.mGlyphs.deinit(keep_allocator);
    self.mTexts.deinit(keep_allocator);
    self.mLetterNodes.deinit(keep_allocator);
    self.mScenes.deinit(keep_allocator);
}

/// Holds nothing, its memory kept: for when the entities it names are gone
pub fn Clear(self: *WorldBVH) void {
    self.mGame.Clear();
    self.mOverlay.Clear();
    self.mGlyphs.clearRetainingCapacity();
    self.mTexts.clearRetainingCapacity();
    self.mLetterNodes.clearRetainingCapacity();
    self.mScenes.clearRetainingCapacity();
}

/// `text`'s letters, each one's leaf item index its place here
pub fn Letters(self: *const WorldBVH, text: TextEntry) []const TextLayout.GlyphPlacement {
    return self.mGlyphs.items[text.FirstGlyph..][0..text.GlyphCount];
}

/// The tree over `text`'s letters, a tree of its own (TextEntry)
pub fn LetterTree(self: *const WorldBVH, text: TextEntry) []const BVH.Node {
    return self.mLetterNodes.items[text.FirstNode..][0..text.NodeCount];
}

/// A laid out letter's box in its text's layout space: around its glyph box (its pen plus PlaneCenter, out by
/// HalfExtents), as thin as a drawn letter. Placed by the text's transform (ShapeGeometry.GlyphBox) it is the letter
pub fn LetterBounds(glyph: TextLayout.GlyphPlacement) Aabb {
    const center = glyph.Pen.AddVec(glyph.PlaneCenter);
    return .{
        .Min = .{ .x = center.x - glyph.HalfExtents.x, .y = center.y - glyph.HalfExtents.y, .z = -SDFFunctions.THICKNESS_2D },
        .Max = .{ .x = center.x + glyph.HalfExtents.x, .y = center.y + glyph.HalfExtents.y, .z = SDFFunctions.THICKNESS_2D },
    };
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

/// A text item's box (in its tree's units) from where its text is now: around its whole text area when it is clicked
/// (`mask` has BVH.Mask.PICK, ShapeGeometry.TextBoxFromMetrics), and around its letters when they are drawn (RENDER,
/// its letter tree's root placed by the text's transform). What the build and a refit both box a text with
pub fn TextBounds(self: *const WorldBVH, transform: *const TransformComponent, text: *const TextComponent, entry: TextEntry, mask: u4) Aabb {
    var bounds = Aabb.empty;
    if (mask & BVH.Mask.PICK != 0) bounds = bounds.Union(BoxBounds(ShapeGeometry.TextBoxFromMetrics(transform, text, entry.Metrics, null)));
    if (mask & BVH.Mask.RENDER != 0 and entry.NodeCount > 0) {
        const ink = self.LetterTree(entry)[0].Bounds();
        const params = ShapeGeometry.GetTextParams(transform, text);
        bounds = bounds.Union(BoxBounds(ShapeGeometry.TextInkBox(transform, params, .{ .x = ink.Min.x, .y = ink.Min.y }, .{ .x = ink.Max.x, .y = ink.Max.y }, null)));
    }
    return bounds;
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
pub fn MergeBounds(scratch_allocator: std.mem.Allocator, root: Entity) !?Aabb {
    var programs: SDFCompiler.Programs = .{};
    const compiled = try SDFCompiler.Compile(scratch_allocator, root, null, &programs);
    if (compiled.Parts.Count == 0) return null;
    return BoxBounds(ShapeGeometry.MergeBox(compiled));
}
