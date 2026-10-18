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
const EngineContext = @import("EngineContext.zig");
const WorldManager = @import("WorldManager.zig");
const BVH = @import("BVH.zig");
const Aabb = @import("../Math/Aabb.zig");
const SDFFunctions = @import("../Math/SDFFunctions.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;

const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");
const TextLayout = @import("../Renderer/TextLayout.zig");
const SDFCompiler = @import("../Renderer/SDFCompiler.zig");
const QuadDrawsNothing = @import("../Renderer/Renderer2D.zig").QuadDrawsNothing;
const CollisionManager = @import("../Physics/CollisionManager.zig");

const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const LayerType = @import("../ECSComponents/Scene/SceneComponent.zig").LayerType;
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const GameLayerTag = EntityComponents.GameLayerTag;
const OverlayLayerTag = EntityComponents.OverlayLayerTag;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;
const TextAsset = @import("../ECSComponents/AComponents.zig").TextAsset;

const WorldBVH = @This();

/// How many scenes a world can have items in: a view says which it shows as one bit each (SceneBits)
pub const MAX_SCENES: usize = 64;

pub const ItemKind = enum(u8) {
    Quad,
    Glyph,
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
    /// a glyph's placement in mGlyphs, which a refit places again without laying its text out again. 0 for the rest
    Glyph: u32 = 0,
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

    fn Add(self: *LayerTree, engine_allocator: std.mem.Allocator, item: WorldItem, bounds: Aabb, mask: u4) !void {
        try self.mBVHItems.append(engine_allocator, .{ .Id = @intCast(self.mItems.items.len), .Bounds = bounds, .Mask = mask });
        try self.mItems.append(engine_allocator, item);
    }

    /// The tree over what was added, and the items put in its order
    fn Build(self: *LayerTree, engine_allocator: std.mem.Allocator, frame_allocator: std.mem.Allocator) !void {
        try BVH.Build(engine_allocator, self.mBVHItems.items, &self.mNodes);
        const added = try frame_allocator.dupe(WorldItem, self.mItems.items);
        for (self.mBVHItems.items, self.mItems.items, 0..) |*bvh_item, *item, i| {
            item.* = added[bvh_item.Id];
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
/// the scenes items are in, each one's place here its SceneSlot
mScenes: std.ArrayList(Scene.Type) = .empty,

pub fn Deinit(self: *WorldBVH, engine_allocator: std.mem.Allocator) void {
    self.mGame.Deinit(engine_allocator);
    self.mOverlay.Deinit(engine_allocator);
    self.mGlyphs.deinit(engine_allocator);
    self.mScenes.deinit(engine_allocator);
}

/// Holds nothing, its memory kept: for when the entities it names are gone
pub fn Clear(self: *WorldBVH) void {
    self.mGame.Clear();
    self.mOverlay.Clear();
    self.mGlyphs.clearRetainingCapacity();
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

/// The fonts the engine's texts are laid out in: their TextAsset
const AssetFonts = struct {
    mEngineContext: *EngineContext,

    pub fn Get(self: AssetFonts, text: *const TextComponent) !*const TextAsset {
        return text.mTextAssetHandle.GetAsset(self.mEngineContext, TextAsset);
    }
};

/// Both trees over everything `world` has now. World transforms must be up to date
pub fn Build(self: *WorldBVH, engine_context: *EngineContext, world: *WorldManager) !void {
    try self.BuildWith(engine_context, world, AssetFonts{ .mEngineContext = engine_context });
}

/// Build with texts laid out in the fonts `fonts.Get(text)` gives, so a test can lay out in a stand in font
pub fn BuildWith(self: *WorldBVH, engine_context: *EngineContext, world: *WorldManager, fonts: anytype) !void {
    const zone = Tracy.ZoneInit("WorldBVH::Build", @src());
    defer zone.Deinit();

    const engine_allocator = engine_context.EngineAllocator();
    const frame_allocator = engine_context.FrameAllocator();
    self.Clear();

    var builder = Builder{ .mBVH = self, .mEngineAllocator = engine_allocator, .mFrameAllocator = frame_allocator };

    //what is drawn and clicked: the same as a view's gather (ShapeGeometry.GatherViewShapes), only over every scene.
    //Folded away by a collapsed layout item is neither, and that only changes at the commit
    const hidden = GroupQuery{ .Component = LayoutHiddenTag };
    const surfaces = GroupQuery{ .Component = SurfaceComponent };
    const visuals_query = GroupQuery{ .Not = .{ .mFirst = &surfaces, .mSecond = &hidden } };
    const visuals = try world.GetEntityGroup(frame_allocator, visuals_query);
    for (visuals.items) |entity_id| {
        const entity = world.GetEntity(entity_id);
        //a part of a merge is its root's one item
        if (ShapeGeometry.MergeRootOf(entity)) |root| {
            const seen = try builder.mMerges.getOrPut(frame_allocator, root.mID);
            if (!seen.found_existing) try builder.AddMerge(root);
            continue;
        }
        //hidden by its surface: left out, so a surface shown mid frame is in the next frame's tree
        const surface = entity.GetComponent(SurfaceComponent).?;
        if (!surface.mShouldRender) continue;
        const transform = entity.GetComponent(TransformComponent) orelse continue;

        if (ShapeGeometry.QuadOf(entity)) |quad| {
            //invisible quads aren't drawn, but they still take clicks (row buttons)
            const mask = if (QuadDrawsNothing(surface.*)) BVH.Mask.PICK else BVH.Mask.RENDER | BVH.Mask.PICK;
            try builder.Add(entity, .Quad, 0, BoxBounds(ShapeGeometry.QuadBox(transform, quad.*, surface.mBorderWidth, null)), mask);
        }
        if (entity.GetComponent(TextComponent)) |text| try builder.AddGlyphs(entity, transform, text, try fonts.Get(text));
    }

    //what physics collides: every collider, the same as its own query (CollisionManager.QueryColliderGroups)
    const colliders = try world.GetEntityGroup(frame_allocator, .{ .Component = ColliderComponent });
    for (colliders.items) |entity_id| {
        const entity = world.GetEntity(entity_id);
        const bounds = ColliderBounds(entity) orelse continue;
        try builder.Add(entity, .Collider, 0, bounds, BVH.Mask.PHYSICS);
    }

    try self.mGame.Build(engine_allocator, frame_allocator);
    try self.mOverlay.Build(engine_allocator, frame_allocator);
    zone.Value(self.mGame.mItems.items.len + self.mOverlay.mItems.items.len);
}

/// Every refit mask at once: what is drawn, clicked and collided
pub const ALL_ITEMS: u4 = BVH.Mask.RENDER | BVH.Mask.PICK | BVH.Mask.PHYSICS;

/// The boxes of the items with any of `mask` from where they are now, and both trees' boxes from every item's: for after
/// things have moved. Items left out keep the box they had, which every node still holds, so the tree stays right for a
/// walk of `mask`: a physics substep only places colliders again (BVH.Mask.PHYSICS), and the refit before rendering
/// places everything (ALL_ITEMS). The items and tree stay as built, so a refit is right for as long as the same things
/// are in the world, which is until the next commit. An item whose entity has lost what places it keeps its box
pub fn Refit(self: *WorldBVH, engine_context: *EngineContext, world: *WorldManager, mask: u4) void {
    const zone = Tracy.ZoneInit("WorldBVH::Refit", @src());
    defer zone.Deinit();

    var placed: usize = 0;
    for ([_]*LayerTree{ &self.mGame, &self.mOverlay }) |tree| {
        for (tree.mItems.items, tree.mBVHItems.items) |item, *bvh_item| {
            if (bvh_item.Mask & mask == 0) continue;
            placed += 1;
            if (self.ItemBounds(engine_context, world, item)) |bounds| bvh_item.Bounds = bounds;
        }
        BVH.Refit(tree.mBVHItems.items, tree.mNodes.items);
    }
    zone.Value(placed);
}

/// Where `item` is now, or null if its entity has lost what places it
fn ItemBounds(self: *const WorldBVH, engine_context: *EngineContext, world: *WorldManager, item: WorldItem) ?Aabb {
    const entity = world.GetEntity(item.Entity);
    //destroyed since the build: deletes happen straight away, so the tree can name an entity that is gone until the
    //next build. Its box stays, and whatever walks the tree checks the same before reading it
    if (!entity.IsActive()) return null;
    switch (item.Kind) {
        .Quad => {
            const transform = entity.GetComponent(TransformComponent) orelse return null;
            const quad = ShapeGeometry.QuadOf(entity) orelse return null;
            const surface = entity.GetComponent(SurfaceComponent) orelse return null;
            return BoxBounds(ShapeGeometry.QuadBox(transform, quad.*, surface.mBorderWidth, null));
        },
        .Glyph => {
            const transform = entity.GetComponent(TransformComponent) orelse return null;
            const text = entity.GetComponent(TextComponent) orelse return null;
            const params = ShapeGeometry.GetTextParams(transform, text);
            return BoxBounds(ShapeGeometry.GlyphBox(transform, params, self.mGlyphs.items[item.Glyph], null));
        },
        .Merge => return MergeBounds(engine_context.FrameAllocator(), entity) catch null,
        .Collider => return ColliderBounds(entity),
    }
}

/// Fills a WorldBVH's two layers during a build
const Builder = struct {
    mBVH: *WorldBVH,
    mEngineAllocator: std.mem.Allocator,
    mFrameAllocator: std.mem.Allocator,
    /// each scene's SceneSlot so far
    mSlots: std.AutoHashMapUnmanaged(Scene.Type, u8) = .empty,
    /// the merges already added, so each is one item however many of its parts there are
    mMerges: std.AutoHashMapUnmanaged(Entity.Type, void) = .empty,

    /// Adds an item to `entity`'s layer, in its scene. Left out if it is in no layer or no scene, the way a view leaves
    /// out an entity with no layer tag
    fn Add(self: *Builder, entity: Entity, kind: ItemKind, glyph: u32, bounds: Aabb, mask: u4) !void {
        const tree = if (entity.HasComponent(OverlayLayerTag))
            &self.mBVH.mOverlay
        else if (entity.HasComponent(GameLayerTag))
            &self.mBVH.mGame
        else
            return;
        const scene = entity.GetComponent(EntitySceneComponent) orelse return;
        const slot = try self.SceneSlot(scene.mScene.mID);
        try tree.Add(self.mEngineAllocator, .{ .Entity = entity.mID, .Kind = kind, .SceneSlot = slot, .Glyph = glyph }, bounds, mask);
    }

    fn SceneSlot(self: *Builder, scene_id: Scene.Type) !u8 {
        const entry = try self.mSlots.getOrPut(self.mFrameAllocator, scene_id);
        if (!entry.found_existing) {
            const scenes = &self.mBVH.mScenes;
            if (scenes.items.len >= MAX_SCENES) {
                _ = self.mSlots.remove(scene_id);
                return error.TooManyScenes;
            }
            entry.value_ptr.* = @intCast(scenes.items.len);
            try scenes.append(self.mEngineAllocator, scene_id);
        }
        return entry.value_ptr.*;
    }

    /// A merge's one item, over the rectangle its parts lie within. One the renderer wouldn't draw is left out too
    fn AddMerge(self: *Builder, root: Entity) !void {
        const found = MergeBounds(self.mFrameAllocator, root) catch |err| switch (err) {
            error.MergeTooDeep => return,
            else => return err,
        };
        const bounds = found orelse return;
        try self.Add(root, .Merge, 0, bounds, BVH.Mask.RENDER | BVH.Mask.PICK);
    }

    /// One item per letter `text` draws, laid out once here and kept for refits and the renderer
    fn AddGlyphs(self: *Builder, entity: Entity, transform: *const TransformComponent, text: *const TextComponent, font: anytype) !void {
        const params = ShapeGeometry.GetTextParams(transform, text);
        const glyphs = &self.mBVH.mGlyphs;
        var layout = TextLayout.Iterator(@TypeOf(font.*)).Init(text.mText.items, font, params.FontSize, params.WrapWidth);
        while (layout.Next()) |glyph| {
            const glyph_ind: u32 = @intCast(glyphs.items.len);
            try glyphs.append(self.mEngineAllocator, glyph);
            const bounds = BoxBounds(ShapeGeometry.GlyphBox(transform, params, glyph, null));
            try self.Add(entity, .Glyph, glyph_ind, bounds, BVH.Mask.RENDER | BVH.Mask.PICK);
        }
    }
};

/// The axis lined up box around an oriented one
pub fn BoxBounds(box: ShapeGeometry.Box) Aabb {
    const axis_x = (Vec3(f32){ .x = 1, .y = 0, .z = 0 }).QuatRotate(box.Rotation);
    const axis_y = (Vec3(f32){ .x = 0, .y = 1, .z = 0 }).QuatRotate(box.Rotation);
    const axis_z = (Vec3(f32){ .x = 0, .y = 0, .z = 1 }).QuatRotate(box.Rotation);
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
fn MergeBounds(frame_allocator: std.mem.Allocator, root: Entity) !?Aabb {
    var programs: SDFCompiler.Programs = .{};
    const compiled = try SDFCompiler.Compile(frame_allocator, root, null, &programs);
    if (compiled.Parts.Count == 0) return null;
    return BoxBounds(ShapeGeometry.MergeBox(compiled));
}
