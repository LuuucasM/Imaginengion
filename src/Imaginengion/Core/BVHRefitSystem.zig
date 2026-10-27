//! Places a world's tree items again from where their entities are now, and both trees' boxes from them: for after
//! things have moved. Items without any of `mask` keep the box they had, which every node still holds, so the tree stays
//! right for a walk of `mask`: a physics substep only places colliders again (BVH.Mask.PHYSICS), and the refit before
//! rendering places everything (WorldBVH.ALL_ITEMS). The items and tree stay as built (BVHBuildSystem), so a refit is
//! right for as long as the same things are in the world, which is until the next commit. An item whose entity has lost
//! what places it keeps its box.
//!
//!     try engine_context.mSystems.RunSystem(BVHRefitSystem, engine_context, &world.mEManager.mECSManager, .{ world, WorldBVH.ALL_ITEMS });
const EngineContext = @import("EngineContext.zig");
const WorldManager = @import("WorldManager.zig");
const WorldBVH = @import("WorldBVH.zig");
const BVH = @import("BVH.zig");
const Aabb = @import("../Math/Aabb.zig");
const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;

pub const Name = "BVHRefit";
pub const Reads = &.{
    TransformComponent,
    EntityComponents.ShapeComponent,
    SurfaceComponent,
    TextComponent,
    EntityComponents.ColliderComponent,
    //how far a collider's body can move in a substep (CollisionManager.SubstepReach)
    EntityComponents.RigidBodyComponent,
    //how a merge's parts combine, compiled for its box (WorldBVH.MergeBounds)
    EntityComponents.CombineOpComponent,
};
pub const Writes = &.{};

pub fn Run(engine_context: *EngineContext, world: *WorldManager, mask: u4) void {
    const bvh = &world.mBVH;
    for ([_]*WorldBVH.LayerTree{ &bvh.mGame, &bvh.mOverlay }) |tree| {
        for (tree.mItems.items, tree.mBVHItems.items) |item, *bvh_item| {
            if (bvh_item.Mask & mask == 0) continue;
            if (ItemBounds(engine_context, world, item)) |bounds| bvh_item.Bounds = bounds;
        }
        BVH.Refit(tree.mBVHItems.items, tree.mNodes.items);
    }
}

/// Where `item` is now, or null if its entity has lost what places it
fn ItemBounds(engine_context: *EngineContext, world: *WorldManager, item: WorldBVH.WorldItem) ?Aabb {
    const bvh = &world.mBVH;
    const entity = world.GetEntity(item.Entity);
    //destroyed since the build: deletes happen straight away, so the tree can name an entity that is gone until the
    //next build. Its box stays, and whatever walks the tree checks the same before reading it
    if (!entity.IsActive()) return null;
    switch (item.Kind) {
        .Quad => {
            const transform = entity.GetComponent(TransformComponent) orelse return null;
            const quad = ShapeGeometry.QuadOf(entity) orelse return null;
            const surface = entity.GetComponent(SurfaceComponent) orelse return null;
            return WorldBVH.BoxBounds(ShapeGeometry.QuadBox(transform, quad.*, surface.mBorderWidth, null));
        },
        .Glyph => {
            const transform = entity.GetComponent(TransformComponent) orelse return null;
            const text = entity.GetComponent(TextComponent) orelse return null;
            const params = ShapeGeometry.GetTextParams(transform, text);
            return WorldBVH.BoxBounds(ShapeGeometry.GlyphBox(transform, params, bvh.mGlyphs.items[item.Index], null));
        },
        .Text => {
            const transform = entity.GetComponent(TransformComponent) orelse return null;
            const text = entity.GetComponent(TextComponent) orelse return null;
            return WorldBVH.BoxBounds(ShapeGeometry.TextBoxFromMetrics(transform, text, bvh.mTexts.items[item.Index], null));
        },
        .Merge => return WorldBVH.MergeBounds(engine_context.FrameAllocator(), entity) catch null,
        .Collider => return WorldBVH.ColliderBounds(entity),
    }
}
