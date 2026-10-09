//! What a view shows, and where each shape actually is in the world for its camera. The one place that
//! answers both, so the renderer drawing a shape and picking clicking on it can never disagree, the same
//! reason rays (CameraRay) and text layout (TextLayout) each have a single home.
const std = @import("std");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
const Vec4 = MathTypes.Vec4;

const OverlayCanvas = @import("../Math/OverlayCanvas.zig");
const CanvasTransform = OverlayCanvas.CanvasTransform;
const SDFFunctions = @import("../Math/SDFFunctions.zig");
const THICKNESS_2D = SDFFunctions.THICKNESS_2D;
const CameraView = @import("Renderer.zig").CameraView;
const TextLayout = @import("TextLayout.zig");

const WorldManager = @import("../Core/WorldManager.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const GameLayerTag = EntityComponents.GameLayerTag;
const OverlayLayerTag = EntityComponents.OverlayLayerTag;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const MaskComponent = EntityComponents.MaskComponent;
const SDFProgram = @import("SDFProgram.zig");
const SDFCompiler = @import("SDFCompiler.zig");
const NO_MASK = SDFProgram.NO_MASK;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const SceneComponent = @import("../ECSComponents/SComponents.zig").SceneComponent;

/// An oriented box in world space, what the renderer uploads and what a ray is tested against.
pub const Box = struct {
    Center: Vec3(f32),
    Rotation: Quat(f32),
    HalfExtents: Vec3(f32),
    //a rounded quad's corners, in world units (x top right, y bottom right, z top left, w bottom left). 0 for a box
    CornerRadii: Vec4(f32) = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
    //a quad's border band, in world units. Only drawn, never part of the shape
    BorderWidth: f32 = 0,
};

/// Everything that is drawn: whatever has a surface, which paints its shape or its text. What the renderer draws and
/// what picking clicks on
pub const VISUALS_QUERY = GroupQuery{ .Component = SurfaceComponent };

/// Which scenes a view shows. The game layer is usually the whole world, which everyone sees; overlays are
/// chosen per view, e.g. the ones a player has (Player.GetOverlayScenes) or every one for the editor camera
pub const ViewScenes = struct {
    Game: union(enum) {
        All,
        /// just this game layer scene, e.g. a template preview
        One: Scene.Type,
        None,
    } = .All,
    Overlays: []const Scene.Type,
};

/// The masks (MaskComponent) a view's shapes are cut by, each one's shape compiled once into a program for the whole
/// view however many shapes are under it. The renderer uploads them as they are, and picking tests with them, both
/// running the same SDFProgram code. Only valid for the frame it was built in
pub const ViewMasks = struct {
    mPrograms: SDFCompiler.Programs = .{},
    mMasks: std.ArrayList(SDFProgram.MaskData) = .empty,
    /// each mask's quad, placed in the world: what culling compares a shape's box with
    mBoxes: std.ArrayList(Box) = .empty,

    /// Whether `point` is kept by mask `mask` and every mask around it: the same test the renderer cuts with
    pub fn Contains(self: *const ViewMasks, mask: u32, point: Vec3(f32)) bool {
        return SDFProgram.InMasks(self.mMasks.items, self.mPrograms.mInstrs.items, self.mPrograms.mParts.items, mask, point);
    }

    /// Whether all of `box` is cut off by mask `mask` or one around it, so none of it is drawn and it doesn't need
    /// sending at all. Only an Intersect mask can cut a whole box off, and it's compared with the mask's quad as if its
    /// corners were square, which can only ever send a box that turns out cut off, never leave out one that isn't
    pub fn CutsOff(self: *const ViewMasks, mask: u32, box: Box) bool {
        var ind = mask;
        while (ind != NO_MASK) {
            const data = self.mMasks.items[ind];
            if (data.Op == .Intersect and OutsideMaskBox(box, self.mBoxes.items[ind])) return true;
            ind = data.Parent;
        }
        return false;
    }
};

/// One entity a view shows, with the canvas that places it for an overlay entity (null in the game layer,
/// whose transforms are already world space), and the mask it is cut by, if any: an index into its view's ViewMasks
pub const ViewShape = struct {
    Entity: Entity,
    Canvas: ?CanvasTransform,
    Mask: u32 = NO_MASK,
};

/// What a view shows (GatherViewShapes): the entities, and the masks they are cut by
pub const ViewShapes = struct {
    Shapes: std.ArrayList(ViewShape) = .empty,
    Masks: ViewMasks = .{},
};

/// A world's screen space in front of this camera, the canvas every one of its overlay scenes is on: their entities'
/// transforms are in canvas units and this is what places them in the world
pub fn WorldCanvas(world: *const WorldManager, camera_view: CameraView) CanvasTransform {
    return OverlayCanvas.ComputeCanvasTransform(
        camera_view.Pose,
        camera_view.TanHalfFov,
        camera_view.TargetHeight,
        world.OverlayPixelsPerUnit(camera_view.TargetHeight, camera_view.DisplayScale),
    );
}

/// Every entity matching `query` that this view shows, each with its canvas: the renderer draws this list and
/// picking tests it, so the two always agree on what a view contains. Overlay scenes come first, all on the world's
/// one canvas, then the game layer, along with the masks they are cut by. Overlay scenes that are gone, or aren't overlays,
/// are left out. Only valid for the frame it was built in
pub fn GatherViewShapes(
    frame_allocator: std.mem.Allocator,
    world: *WorldManager,
    camera_view: CameraView,
    view_scenes: ViewScenes,
    comptime query: GroupQuery,
) !ViewShapes {
    //folded away by a collapsed layout item: neither drawn nor clickable
    const hidden = GroupQuery{ .Component = LayoutHiddenTag };
    const overlay_shapes = GroupQuery{ .And = &[_]GroupQuery{ query, .{ .Component = OverlayLayerTag } } };
    const game_shapes = GroupQuery{ .And = &[_]GroupQuery{ query, .{ .Component = GameLayerTag } } };
    const overlay_query = GroupQuery{ .Not = .{ .mFirst = &overlay_shapes, .mSecond = &hidden } };
    const game_query = GroupQuery{ .Not = .{ .mFirst = &game_shapes, .mSecond = &hidden } };

    var view = ViewShapes{};
    const shapes = &view.Shapes;
    var masks = MaskFinder{ .mAllocator = frame_allocator, .mMasks = &view.Masks };

    const canvas = WorldCanvas(world, camera_view);
    for (view_scenes.Overlays) |scene_id| {
        const scene = world.GetScene(scene_id);
        if (!scene.IsActive() or scene.GetLayer() != .OverlayLayer) continue;

        const entity_ids = try scene.GetEntityGroup(frame_allocator, overlay_query);
        try shapes.ensureUnusedCapacity(frame_allocator, entity_ids.items.len);
        for (entity_ids.items) |entity_id| {
            const entity = world.GetEntity(entity_id);
            shapes.appendAssumeCapacity(.{ .Entity = entity, .Canvas = canvas, .Mask = try masks.MaskOf(entity, canvas) });
        }
    }

    const game_ids = switch (view_scenes.Game) {
        .All => try world.GetEntityGroup(frame_allocator, game_query),
        .One => |scene_id| try world.GetScene(scene_id).GetEntityGroup(frame_allocator, game_query),
        .None => return view,
    };
    try shapes.ensureUnusedCapacity(frame_allocator, game_ids.items.len);
    for (game_ids.items) |entity_id| {
        const entity = world.GetEntity(entity_id);
        shapes.appendAssumeCapacity(.{ .Entity = entity, .Canvas = null, .Mask = try masks.MaskOf(entity, null) });
    }

    return view;
}

/// Works out which mask each shape is cut by, compiling each mask the first time one of its shapes asks and remembering
/// it for the rest of the gather: a long scrolled list's rows all ask about the same one
const MaskFinder = struct {
    mAllocator: std.mem.Allocator,
    mMasks: *ViewMasks,
    /// each mask entity's mask, or the one around it for a mask entity with no shape to cut with
    mRegions: std.AutoHashMapUnmanaged(Entity.Type, u32) = .empty,

    /// The mask `entity` is cut by: its nearest parent (or further up) with a MaskComponent. Its own isn't one: the
    /// mask entity's own shape is what it cuts with
    fn MaskOf(self: *MaskFinder, entity: Entity, canvas: ?CanvasTransform) !u32 {
        const region = MaskRegionAbove(entity) orelse return NO_MASK;
        return try self.RegionMask(region, canvas);
    }

    fn RegionMask(self: *MaskFinder, region: Entity, canvas: ?CanvasTransform) anyerror!u32 {
        if (self.mRegions.get(region.mID)) |known| return known;

        //the mask around it is added first, so following parents always ends
        const outer = try self.MaskOf(region, canvas);
        var mask = outer;
        if (try SDFCompiler.CompileShape(self.mAllocator, region, canvas, &self.mMasks.mPrograms)) |compiled| {
            mask = @intCast(self.mMasks.mMasks.items.len);
            try self.mMasks.mMasks.append(self.mAllocator, .{
                .First = compiled.Range.First,
                .Count = compiled.Range.Count,
                .Op = region.GetComponent(MaskComponent).?.mOp,
                .Parent = outer,
            });
            //CompileShape only gives a program to a quad with a transform
            const box = QuadBox(region.GetComponent(TransformComponent).?, QuadOf(region).?.*, 0, canvas);
            try self.mMasks.mBoxes.append(self.mAllocator, box);
        }

        try self.mRegions.put(self.mAllocator, region.mID, mask);
        return mask;
    }
};

/// The nearest entity above `entity` (its parent, or further up) with a MaskComponent
fn MaskRegionAbove(entity: Entity) ?Entity {
    var current = entity;
    while (current.GetComponent(EntityChildComponent)) |child_component| {
        current = Entity{ .mID = child_component.mParent, .mManager = entity.mManager };
        if (current.HasComponent(MaskComponent)) return current;
    }
    return null;
}

/// Whether all of `box` is outside a mask's quad `mask_box` across the quad's plane, through any depth, the way a mask
/// cuts. Compares the box's reach across the plane with the quad's rectangle, corners square, which never says outside
/// for a box that isn't
pub fn OutsideMaskBox(box: Box, mask_box: Box) bool {
    const center = box.Center.SubVec(mask_box.Center).InvQuatRotate(mask_box.Rotation);
    //the box's own axes, as seen in the mask quad's space
    const axis_x = (Vec3(f32){ .x = 1, .y = 0, .z = 0 }).QuatRotate(box.Rotation).InvQuatRotate(mask_box.Rotation);
    const axis_y = (Vec3(f32){ .x = 0, .y = 1, .z = 0 }).QuatRotate(box.Rotation).InvQuatRotate(mask_box.Rotation);
    const axis_z = (Vec3(f32){ .x = 0, .y = 0, .z = 1 }).QuatRotate(box.Rotation).InvQuatRotate(mask_box.Rotation);
    const half = box.HalfExtents;
    const reach_x = @abs(axis_x.x) * half.x + @abs(axis_y.x) * half.y + @abs(axis_z.x) * half.z;
    const reach_y = @abs(axis_x.y) * half.x + @abs(axis_y.y) * half.y + @abs(axis_z.y) * half.z;
    return @abs(center.x) - reach_x > mask_box.HalfExtents.x or @abs(center.y) - reach_y > mask_box.HalfExtents.y;
}

/// An entity's shape, if it is a quad
pub fn QuadOf(entity: Entity) ?*ShapeComponent.Quad {
    const shape = entity.GetComponent(ShapeComponent) orelse return null;
    return shape.GetQuad();
}

/// The quad's own size grown by its scale (and everything above it in the hierarchy), placed by the
/// canvas for an overlay quad. Thickness stays THICKNESS_2D in world units either way. `border_width` is its surface's
/// border, which grows with it; 0 where only the shape matters, like picking
pub fn QuadBox(transform: *const TransformComponent, quad: ShapeComponent.Quad, border_width: f32, canvas: ?CanvasTransform) Box {
    const world_scale = transform.GetWorldScale();
    var center = transform.GetWorldPosition();
    var rotation = transform.GetWorldRotation();
    var half_x = quad.Size.x * world_scale.x * 0.5;
    var half_y = quad.Size.y * world_scale.y * 0.5;

    if (canvas) |c| {
        center = c.ToWorldPoint(center);
        rotation = c.ToWorldRotation(rotation);
        half_x *= c.Scale;
        half_y *= c.Scale;
    }

    //corners and border grow with the quad, by its smaller axis so a rounded corner stays round. Neither can be
    //more than half the smaller side: past that the corners would overlap, and the border would cover it all
    const size_scale = @min(world_scale.x, world_scale.y) * if (canvas) |c| c.Scale else 1.0;
    const most = @min(half_x, half_y);
    const radii = quad.CornerRadii.MulScalar(size_scale);

    return .{
        .Center = center,
        .Rotation = rotation,
        .HalfExtents = .{ .x = half_x, .y = half_y, .z = THICKNESS_2D },
        .CornerRadii = .{
            .x = std.math.clamp(radii.x, 0, most),
            .y = std.math.clamp(radii.y, 0, most),
            .z = std.math.clamp(radii.z, 0, most),
            .w = std.math.clamp(radii.w, 0, most),
        },
        .BorderWidth = std.math.clamp(border_width * size_scale, 0, most),
    };
}

/// What TextLayout needs for a text component, with its scale already applied. Text only grows evenly,
/// so it takes the largest scale axis, like a sphere collider. The font size and the bounds grow
/// together, which keeps the wrapping on the same words at any scale.
pub const TextParams = struct {
    FontSize: f32,
    LeftBound: f32, //how far the text runs left of its transform; layout lines start at x = 0, so they shift left by this
    RightBound: f32,
    WrapWidth: f32,
};

pub fn GetTextParams(transform: *const TransformComponent, text: *const TextComponent) TextParams {
    const world_scale = transform.GetWorldScale();
    const text_scale = @max(world_scale.x, @max(world_scale.y, world_scale.z));
    const left = text.mBounds.x * text_scale;
    const right = text.mBounds.y * text_scale;
    return .{
        .FontSize = text.mFontSize * text_scale,
        .LeftBound = left,
        .RightBound = right,
        .WrapWidth = left + right,
    };
}

/// The whole text area: across the full left to right bounds, and from the first line's ascender down
/// to the last line's descender, since the bounds say nothing about height. Placed by the text's own
/// transform, then by the canvas for overlay text. Generic over the font like TextLayout, so a test
/// can measure with a stand in; the engine always passes TextAsset.
pub fn TextBox(comptime FontT: type, transform: *const TransformComponent, text: *const TextComponent, font: *const FontT, canvas: ?CanvasTransform) Box {
    const params = GetTextParams(transform, text);
    const metrics = TextLayout.Measure(FontT, text.mText.items, font, params.FontSize, params.WrapWidth);

    //in the text's own space: x from -left to +right around the transform, y over the laid out lines
    const local_center = Vec3(f32){
        .x = (params.RightBound - params.LeftBound) * 0.5,
        .y = (metrics.Min.y + metrics.Max.y) * 0.5,
        .z = 0,
    };
    var half_x = (params.LeftBound + params.RightBound) * 0.5;
    var half_y = (metrics.Max.y - metrics.Min.y) * 0.5;

    const text_rotation = transform.GetWorldRotation();
    var center = transform.GetWorldPosition().AddVec(local_center.QuatRotate(text_rotation));
    var rotation = text_rotation;

    if (canvas) |c| {
        center = c.ToWorldPoint(center);
        rotation = c.ToWorldRotation(rotation);
        half_x *= c.Scale;
        half_y *= c.Scale;
    }

    return .{
        .Center = center,
        .Rotation = rotation,
        .HalfExtents = .{ .x = half_x, .y = half_y, .z = THICKNESS_2D },
    };
}

/// A box collider: its own size grown by its scale, in its entity's real rotation, the same box the physics
/// tests. Its corner radius is not rounded off here: rays test the sharp box. Placed by the canvas for an overlay
/// entity, the same as its visuals.
pub fn ColliderBox(transform: *const TransformComponent, collider: *const ColliderComponent, canvas: ?CanvasTransform) Box {
    var center = transform.GetWorldPosition();
    var rotation = transform.GetWorldRotation();
    var half_extents = collider.GetWorldHalfExtents(transform.GetWorldScale());

    if (canvas) |c| {
        center = c.ToWorldPoint(center);
        rotation = c.ToWorldRotation(rotation);
        half_extents = c.ToWorldVector(half_extents);
    }

    return .{ .Center = center, .Rotation = rotation, .HalfExtents = half_extents };
}

pub const Sphere = struct {
    Center: Vec3(f32),
    Radius: f32,
};

/// A sphere collider: its radius grown by its largest scale axis, placed by the canvas for an overlay entity.
pub fn ColliderSphere(transform: *const TransformComponent, collider: *const ColliderComponent, canvas: ?CanvasTransform) Sphere {
    var center = transform.GetWorldPosition();
    var radius = collider.GetWorldRadius(transform.GetWorldScale());

    if (canvas) |c| {
        center = c.ToWorldPoint(center);
        radius *= c.Scale;
    }

    return .{ .Center = center, .Radius = radius };
}
