//! Builds a world's trees (WorldBVH) over everything it has now: what is drawn and clicked, and every collider. Run once
//! a frame right after the end-of-frame commit, after the world transform pass (WorldManager.BuildBVH), so the set of
//! items can't change until the next one:
//!
//!     try engine_context.mSystems.RunSystem(BVHBuildSystem, engine_context, &world.mEManager.mECSManager, .{ world, BVHBuildSystem.AssetFonts{ .mEngineContext = engine_context } });
//!
//! `fonts.Get(text)` gives the font a text is laid out in, so a test can lay out in a stand in font.
const std = @import("std");
const Tracy = @import("Tracy.zig");
const EngineContext = @import("EngineContext.zig");
const WorldManager = @import("WorldManager.zig");
const WorldBVH = @import("WorldBVH.zig");
const LayerTree = WorldBVH.LayerTree;
const ItemKind = WorldBVH.ItemKind;
const BoxBounds = WorldBVH.BoxBounds;
const ColliderBounds = WorldBVH.ColliderBounds;
const MergeBounds = WorldBVH.MergeBounds;
const MAX_SCENES = WorldBVH.MAX_SCENES;
const BVH = @import("BVH.zig");
const Aabb = @import("../Math/Aabb.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;

const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");
const TextLayout = @import("../Renderer/TextLayout.zig");
const QuadDrawsNothing = @import("../Renderer/Renderer2D.zig").QuadDrawsNothing;

const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const GameLayerTag = EntityComponents.GameLayerTag;
const OverlayLayerTag = EntityComponents.OverlayLayerTag;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;
const TextAsset = @import("../ECSComponents/AComponents.zig").TextAsset;

pub const Name = "BVHBuild";
pub const Reads = &.{
    SurfaceComponent,
    TransformComponent,
    ShapeComponent,
    TextComponent,
    ColliderComponent,
    //each item's scene
    EntitySceneComponent,
    //how far a collider's body can move in a substep (CollisionManager.SubstepReach)
    RigidBodyComponent,
    //how a merge's parts combine, compiled for its box (WorldBVH.MergeBounds)
    EntityComponents.CombineOpComponent,
};
pub const Writes = &.{};

/// The fonts the engine's texts are laid out in: their TextAsset
pub const AssetFonts = struct {
    mEngineContext: *EngineContext,

    pub fn Get(self: AssetFonts, text: *const TextComponent) !*const TextAsset {
        return text.mTextAssetHandle.GetAsset(self.mEngineContext, TextAsset);
    }
};

/// Both of the world's trees over everything it has now. World transforms must be up to date
pub fn Run(engine_context: *EngineContext, world: *WorldManager, fonts: anytype) anyerror!void {
    const bvh = &world.mBVH;
    const engine_allocator = engine_context.EngineAllocator();
    const frame_allocator = engine_context.FrameAllocator();
    bvh.Clear();

    var builder = Builder{ .mBVH = bvh, .mEngineAllocator = engine_allocator, .mFrameAllocator = frame_allocator };

    try builder.AddVisuals(world, fonts);
    try builder.AddColliders(world);

    try bvh.mGame.Build(engine_allocator, frame_allocator);
    try bvh.mOverlay.Build(engine_allocator, frame_allocator);
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

    /// What is drawn and clicked: the same as a view's gather (ShapeGeometry.GatherViewShapes), only over every scene.
    /// Folded away by a collapsed layout item is neither, and that only changes at the commit
    fn AddVisuals(self: *Builder, world: *WorldManager, fonts: anytype) !void {
        const zone = Tracy.ZoneInit("WorldBVH::AddVisuals", @src());
        defer zone.Deinit();

        const hidden = GroupQuery{ .Component = LayoutHiddenTag };
        const surfaces = GroupQuery{ .Component = SurfaceComponent };
        const visuals_query = GroupQuery{ .Not = .{ .mFirst = &surfaces, .mSecond = &hidden } };
        const visuals = try world.GetEntityGroup(self.mFrameAllocator, visuals_query);
        zone.Value(visuals.items.len);
        for (visuals.items) |entity_id| {
            const entity = world.GetEntity(entity_id);
            //a part of a merge is its root's one item
            if (ShapeGeometry.MergeRootOf(entity)) |root| {
                const seen = try self.mMerges.getOrPut(self.mFrameAllocator, root.mID);
                if (!seen.found_existing) try self.AddMerge(root);
                continue;
            }
            //hidden by its surface: left out, so a surface shown mid frame is in the next frame's tree
            const surface = entity.GetComponent(SurfaceComponent).?;
            if (!surface.mShouldRender) continue;
            const transform = entity.GetComponent(TransformComponent) orelse continue;
            const quad = ShapeGeometry.QuadOf(entity);
            const text = entity.GetComponent(TextComponent);
            if (quad == null and text == null) continue;
            //where all its items go, its quad's and every letter's, found once
            const placement = try self.PlacementOf(entity, ShapeGeometry.MaskRegionAbove(entity)) orelse continue;

            if (quad) |q| {
                //invisible quads aren't drawn, but they still take clicks (row buttons)
                const mask = if (QuadDrawsNothing(surface.*)) BVH.Mask.PICK else BVH.Mask.RENDER | BVH.Mask.PICK;
                try self.AddTo(placement, entity, .Quad, 0, BoxBounds(ShapeGeometry.QuadBox(transform, q.*, surface.mBorderWidth, null)), mask);
            }
            if (text) |t| try self.AddText(placement, entity, transform, t, try fonts.Get(t));
        }
    }

    /// What physics collides: every collider, the same as its own query (CollisionManager.QueryColliderGroups)
    fn AddColliders(self: *Builder, world: *WorldManager) !void {
        const zone = Tracy.ZoneInit("WorldBVH::AddColliders", @src());
        defer zone.Deinit();

        const colliders = try world.GetEntityGroup(self.mFrameAllocator, .{ .Component = ColliderComponent });
        zone.Value(colliders.items.len);
        for (colliders.items) |entity_id| {
            const entity = world.GetEntity(entity_id);
            const bounds = ColliderBounds(entity) orelse continue;
            try self.Add(entity, .Collider, 0, bounds, BVH.Mask.PHYSICS);
        }
    }

    /// Where an entity's items go: its layer's tree, its scene's slot, and what its mask is cut by
    const Placement = struct {
        Tree: *LayerTree,
        SceneSlot: u8,
        MaskRegion: Entity.Type,
    };

    /// `entity`'s placement, cut by `mask_region` when drawn. Null if it is in no layer or no scene, which leaves its
    /// items out the way a view leaves out an entity with no layer tag
    fn PlacementOf(self: *Builder, entity: Entity, mask_region: ?Entity) !?Placement {
        const tree = if (entity.HasComponent(OverlayLayerTag))
            &self.mBVH.mOverlay
        else if (entity.HasComponent(GameLayerTag))
            &self.mBVH.mGame
        else
            return null;
        const scene = entity.GetComponent(EntitySceneComponent) orelse return null;
        return .{
            .Tree = tree,
            .SceneSlot = try self.SceneSlot(scene.mScene.mID),
            .MaskRegion = if (mask_region) |region| region.mID else Entity.NullObject,
        };
    }

    fn AddTo(self: *Builder, placement: Placement, entity: Entity, kind: ItemKind, index: u32, bounds: Aabb, mask: u4) !void {
        try placement.Tree.Add(self.mEngineAllocator, .{
            .Entity = entity.mID,
            .Kind = kind,
            .SceneSlot = placement.SceneSlot,
            .Index = index,
            .MaskRegion = placement.MaskRegion,
        }, bounds, mask);
    }

    /// Adds an item no mask cuts to `entity`'s layer, in its scene, if it has a placement
    fn Add(self: *Builder, entity: Entity, kind: ItemKind, index: u32, bounds: Aabb, mask: u4) !void {
        const placement = try self.PlacementOf(entity, null) orelse return;
        try self.AddTo(placement, entity, kind, index, bounds, mask);
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
        const zone = Tracy.ZoneInit("WorldBVH::AddMerge", @src());
        defer zone.Deinit();

        const found = MergeBounds(self.mFrameAllocator, root) catch |err| switch (err) {
            error.MergeTooDeep => return,
            else => return err,
        };
        const bounds = found orelse return;
        const placement = try self.PlacementOf(root, ShapeGeometry.MaskRegionAbove(root)) orelse return;
        try self.AddTo(placement, root, .Merge, 0, bounds, BVH.Mask.RENDER | BVH.Mask.PICK);
    }

    /// One item per letter `text` draws, laid out once here and kept for refits and the renderer, and one for the whole
    /// text that clicks land on, from the size the same layout measured. All of them go where `placement` says
    fn AddText(self: *Builder, placement: Placement, entity: Entity, transform: *const TransformComponent, text: *const TextComponent, font: anytype) !void {
        const zone = Tracy.ZoneInit("WorldBVH::AddText", @src());
        defer zone.Deinit();

        const params = ShapeGeometry.GetTextParams(transform, text);
        const glyphs = &self.mBVH.mGlyphs;
        const first_glyph = glyphs.items.len;
        var layout = TextLayout.Iterator(@TypeOf(font.*)).Init(text.mText.items, font, params.FontSize, params.WrapWidth);
        while (layout.Next()) |glyph| {
            const glyph_ind: u32 = @intCast(glyphs.items.len);
            try glyphs.append(self.mEngineAllocator, glyph);
            const bounds = BoxBounds(ShapeGeometry.GlyphBox(transform, params, glyph, null));
            try self.AddTo(placement, entity, .Glyph, glyph_ind, bounds, BVH.Mask.RENDER);
        }

        zone.Value(glyphs.items.len - first_glyph);

        const texts = &self.mBVH.mTexts;
        const text_ind: u32 = @intCast(texts.items.len);
        const metrics = layout.GetMetrics();
        try texts.append(self.mEngineAllocator, metrics);
        try self.AddTo(placement, entity, .Text, text_ind, BoxBounds(ShapeGeometry.TextBoxFromMetrics(transform, text, metrics, null)), BVH.Mask.PICK);
    }
};
