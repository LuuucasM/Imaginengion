//! Builds a world's trees (WorldBVH) over everything it has now: what is drawn and clicked, and every collider. Run once
//! a frame right after the end-of-frame commit, after the world transform pass (WorldManager.BuildBVH), so the set of
//! items can't change until the next one:
//!
//!     try engine_context.mSystems.RunSystem(BVHBuildSystem, engine_context, .{ world, BVHBuildSystem.AssetFonts{ .mEngineContext = engine_context } });
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
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const MaskComponent = EntityComponents.MaskComponent;
const MergeComponent = EntityComponents.MergeComponent;
const MainObjectComponent = EntityComponents.MainObjectComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const EntityECS = @import("../ECSManagers/EManager.zig").ECSManagerT;
const Vec2 = @import("../Math/MathTypes.zig").Vec2;
const GameLayerTag = EntityComponents.GameLayerTag;
const OverlayLayerTag = EntityComponents.OverlayLayerTag;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;
const TextAsset = @import("../ECSComponents/AComponents.zig").TextAsset;

pub const Name = "BVHBuild";

/// The fonts the engine's texts are laid out in: their TextAsset
pub const AssetFonts = struct {
    mEngineContext: *EngineContext,

    pub fn Get(self: AssetFonts, text: *const TextComponent) !*const TextAsset {
        return text.mTextAssetHandle.GetAsset(self.mEngineContext, TextAsset);
    }
};

/// Both of the world's trees over everything it has now. World transforms must be up to date
pub fn Run(engine_context: *EngineContext, world: *WorldManager, fonts: anytype) anyerror!void {
    engine_context.mTransactions.CheckMainThread("Building the BVH");
    const bvh = &world.mBVH;
    const engine_allocator = engine_context.EngineAllocator();
    const frame_allocator = engine_context.FrameAllocator();
    bvh.Clear();

    var builder = Builder{
        .mBVH = bvh,
        .mEngineAllocator = engine_allocator,
        .mFrameAllocator = frame_allocator,
        .mAncestry = try Ancestry.Init(frame_allocator, world),
    };

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
    /// each mask entity's room so far (RoomOf)
    mRooms: std.AutoHashMapUnmanaged(Entity.Type, []const ShapeGeometry.Box) = .empty,
    /// the merge and mask each entity is under, each ancestor worked out once
    mAncestry: Ancestry = undefined,

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
            if (try self.mAncestry.MergeRootOf(entity)) |root| {
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
            //where all its items go, its quad's and every letter's, and what its masks leave room for, found once
            const mask_region = try self.mAncestry.MaskRegionAbove(entity);
            const placement = try self.PlacementOf(entity, mask_region) orelse continue;
            const room = try self.RoomOf(mask_region);

            if (quad) |q| {
                const box = ShapeGeometry.QuadBox(transform, q.*, surface.mBorderWidth, null);
                if (!CutOff(room, box)) {
                    //invisible quads aren't drawn, but they still take clicks (row buttons)
                    const mask = if (QuadDrawsNothing(surface.*)) BVH.Mask.PICK else BVH.Mask.RENDER | BVH.Mask.PICK;
                    try self.AddTo(placement, entity, .Quad, 0, BoxBounds(box), mask);
                }
            }
            if (text) |t| try self.AddText(placement, entity, transform, t, try fonts.Get(t), room);
        }
    }

    /// The room the masks above an entity leave it, from `region` (its MaskRegionAbove) out: each Intersect mask's quad,
    /// grown by CULL_MARGIN, nearest first. Found once per mask for the whole build, however many things are under it.
    /// Matches what the renderer and picking cut with (MaskFinder.RegionMask): a mask with no quad cuts nothing, and a
    /// Subtract one can't cut a whole box off
    fn RoomOf(self: *Builder, region: ?Entity) anyerror![]const ShapeGeometry.Box {
        const mask_entity = region orelse return &.{};
        if (self.mRooms.get(mask_entity.mID)) |known| return known;

        //the masks around it first, so following parents always ends
        const outer = try self.RoomOf(ShapeGeometry.MaskRegionAbove(mask_entity));
        var room = outer;
        const cuts_off = mask_entity.GetComponent(MaskComponent).?.mOp == .Intersect;
        const transform = mask_entity.GetComponent(TransformComponent);
        const quad = ShapeGeometry.QuadOf(mask_entity);
        if (cuts_off and transform != null and quad != null) {
            var box = ShapeGeometry.QuadBox(transform.?, quad.?.*, 0, null);
            box.HalfExtents.x *= 1 + 2 * CULL_MARGIN;
            box.HalfExtents.y *= 1 + 2 * CULL_MARGIN;
            const boxes = try self.mFrameAllocator.alloc(ShapeGeometry.Box, outer.len + 1);
            boxes[0] = box;
            @memcpy(boxes[1..], outer);
            room = boxes;
        }
        try self.mRooms.put(self.mFrameAllocator, mask_entity.mID, room);
        return room;
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
    /// text that clicks land on, from the size the same layout measured. All of them go where `placement` says. Those
    /// outside the `room` its masks leave (RoomOf) are left out: all its letters at once when all its ink is, and one by
    /// one only for a text across a mask's edge
    fn AddText(self: *Builder, placement: Placement, entity: Entity, transform: *const TransformComponent, text: *const TextComponent, font: anytype, room: []const ShapeGeometry.Box) !void {
        const zone = Tracy.ZoneInit("WorldBVH::AddText", @src());
        defer zone.Deinit();

        const params = ShapeGeometry.GetTextParams(transform, text);
        const glyphs = &self.mBVH.mGlyphs;
        const first_glyph = glyphs.items.len;
        var layout = TextLayout.Iterator(@TypeOf(font.*)).Init(text.mText.items, font, params.FontSize, params.WrapWidth);
        //the letters' ink in the layout's own space, so the whole text is checked against its masks at once
        var ink_min = Vec2(f32){ .x = std.math.inf(f32), .y = std.math.inf(f32) };
        var ink_max = Vec2(f32){ .x = -std.math.inf(f32), .y = -std.math.inf(f32) };
        while (layout.Next()) |glyph| {
            try glyphs.append(self.mEngineAllocator, glyph);
            const center = glyph.Pen.AddVec(glyph.PlaneCenter);
            ink_min = .{ .x = @min(ink_min.x, center.x - glyph.HalfExtents.x), .y = @min(ink_min.y, center.y - glyph.HalfExtents.y) };
            ink_max = .{ .x = @max(ink_max.x, center.x + glyph.HalfExtents.x), .y = @max(ink_max.y, center.y + glyph.HalfExtents.y) };
        }
        zone.Value(glyphs.items.len - first_glyph);

        if (glyphs.items.len > first_glyph) {
            const ink = ShapeGeometry.TextInkBox(transform, params, ink_min, ink_max, null);
            if (CutOff(room, ink)) {
                glyphs.shrinkRetainingCapacity(first_glyph);
            } else {
                const check_each = !WithinRoom(room, ink);
                for (glyphs.items[first_glyph..], first_glyph..) |glyph, glyph_ind| {
                    const box = ShapeGeometry.GlyphBox(transform, params, glyph, null);
                    if (check_each and CutOff(room, box)) continue;
                    try self.AddTo(placement, entity, .Glyph, @intCast(glyph_ind), BoxBounds(box), BVH.Mask.RENDER);
                }
            }
        }

        const metrics = layout.GetMetrics();
        const click_box = ShapeGeometry.TextBoxFromMetrics(transform, text, metrics, null);
        if (CutOff(room, click_box)) return;
        const texts = &self.mBVH.mTexts;
        const text_ind: u32 = @intCast(texts.items.len);
        try texts.append(self.mEngineAllocator, metrics);
        try self.AddTo(placement, entity, .Text, text_ind, BoxBounds(click_box), BVH.Mask.PICK);
    }
};

/// How far past a mask's edge what it cuts still goes in the tree, as a share of the mask's own size, on every side. The
/// tree is built at the top of the frame, so what scrolls into a mask during it is only in the next frame's tree:
/// with a mask's size of room around it, scrolling less than a whole view a frame never leaves a gap at the edge.
/// What a mask cuts off further out is neither drawn, clicked nor refit
pub const CULL_MARGIN: f32 = 1;

/// Whether `box` is wholly outside one of the masks' grown quads in `room` (Builder.RoomOf)
fn CutOff(room: []const ShapeGeometry.Box, box: ShapeGeometry.Box) bool {
    for (room) |mask_box| {
        if (ShapeGeometry.OutsideMaskBox(box, mask_box)) return true;
    }
    return false;
}

/// Whether `box` is wholly inside every one of the masks' grown quads in `room`, so nothing in it can be cut off
fn WithinRoom(room: []const ShapeGeometry.Box, box: ShapeGeometry.Box) bool {
    for (room) |mask_box| {
        if (!ShapeGeometry.InsideMaskBox(box, mask_box)) return false;
    }
    return true;
}

/// The merge (ShapeGeometry.MergeRootOf) and the mask (ShapeGeometry.MaskRegionAbove) each of a world's entities is
/// under, for one build. Asking each entity alone climbs its whole parent chain, again for every sibling and child, so
/// deep UI trees paid for the same ancestors over and over (~290 us a build with every Profiler row open, 2026-11-10).
/// Here each ancestor is worked out once, from its parent's answer, and kept in a table indexed by entity slot. Only
/// right while the hierarchy and the merge, main object and mask components stay as they are, which a build relies on
pub const Ancestry = struct {
    mWorld: *WorldManager,
    /// at each entity's slot, its answers once worked out
    mEntries: []Entry,
    /// the entities being worked out, nearest the known ancestor last
    mClimb: std.ArrayList(Entity.Type) = .empty,
    mAllocator: std.mem.Allocator,

    const Entry = struct {
        Known: bool = false,
        /// the mask the entity is cut by: its nearest ancestor with a MaskComponent
        Above: Entity.Type = Entity.NullObject,
        /// the outermost merge from the entity up to the first main object, both included
        OuterMerge: Entity.Type = Entity.NullObject,

        /// the mask the entity's children are cut by
        fn ChildrenMask(self: Entry, entity: Entity) Entity.Type {
            return if (entity.HasComponent(MaskComponent)) entity.mID else self.Above;
        }
    };

    pub fn Init(allocator: std.mem.Allocator, world: *WorldManager) !Ancestry {
        const entries = try allocator.alloc(Entry, world.mEManager.mECSManager.SlotCount());
        @memset(entries, .{});
        return .{ .mWorld = world, .mEntries = entries, .mAllocator = allocator };
    }

    /// The same as ShapeGeometry.MaskRegionAbove
    pub fn MaskRegionAbove(self: *Ancestry, entity: Entity) !?Entity {
        const found = (try self.Of(entity)).Above;
        return if (found == Entity.NullObject) null else self.mWorld.GetEntity(found);
    }

    /// The same as ShapeGeometry.MergeRootOf
    pub fn MergeRootOf(self: *Ancestry, entity: Entity) !?Entity {
        if (!entity.HasComponent(ShapeComponent) and !entity.HasComponent(MergeComponent)) return null;
        const found = (try self.Of(entity)).OuterMerge;
        return if (found == Entity.NullObject) null else self.mWorld.GetEntity(found);
    }

    /// `entity`'s answers: up its parents to the first one already known (or the top), then each on the way back down
    /// from its parent's. No recursion, however deep
    fn Of(self: *Ancestry, entity: Entity) !Entry {
        const known = self.mEntries[EntityECS.SlotOf(entity.mID)];
        if (known.Known) return known;

        self.mClimb.clearRetainingCapacity();
        //the answers of the topmost entity's parent: there is none, so nothing above
        var parent_entry = Entry{ .Known = true };
        var parent_id: Entity.Type = Entity.NullObject;
        var current = entity;
        while (true) {
            try self.mClimb.append(self.mAllocator, current.mID);
            const child_component = current.GetComponent(EntityChildComponent) orelse break;
            const parent = Entity{ .mID = child_component.mParent, .mManager = entity.mManager };
            const parent_known = self.mEntries[EntityECS.SlotOf(parent.mID)];
            if (parent_known.Known) {
                parent_entry = parent_known;
                parent_id = parent.mID;
                break;
            }
            current = parent;
        }

        var entry = parent_entry;
        var index = self.mClimb.items.len;
        while (index > 0) {
            index -= 1;
            const node = Entity{ .mID = self.mClimb.items[index], .mManager = entity.mManager };
            const own_merge: Entity.Type = if (node.HasComponent(MergeComponent)) node.mID else Entity.NullObject;
            entry = .{
                .Known = true,
                .Above = if (parent_id == Entity.NullObject) Entity.NullObject else parent_entry.ChildrenMask(Entity{ .mID = parent_id, .mManager = entity.mManager }),
                //a main object is a merge's top: nothing above it counts
                .OuterMerge = if (node.HasComponent(MainObjectComponent) or parent_entry.OuterMerge == Entity.NullObject) own_merge else parent_entry.OuterMerge,
            };
            self.mEntries[EntityECS.SlotOf(node.mID)] = entry;
            parent_entry = entry;
            parent_id = node.mID;
        }
        return entry;
    }
};
