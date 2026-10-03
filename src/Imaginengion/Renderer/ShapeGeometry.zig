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
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const GameLayerTag = EntityComponents.GameLayerTag;
const OverlayLayerTag = EntityComponents.OverlayLayerTag;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const ClipComponent = EntityComponents.ClipComponent;
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

/// Everything that is drawn: quads and text. What the renderer draws and what picking clicks on
pub const VISUALS_QUERY = GroupQuery{ .Or = &[_]GroupQuery{
    .{ .Component = QuadComponent },
    .{ .Component = TextComponent },
} };

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

/// A clip region's rectangle in the world (ClipComponent): what is under it is only drawn, and only hit, inside it.
/// Measured in the rectangle's own plane, so it cuts straight through depth
pub const ClipRect = struct {
    Center: Vec3(f32),
    Rotation: Quat(f32),
    HalfExtents: Vec2(f32),
};

/// The clip a shape is cut to, and the region it belongs to: every shape under one region shares it
pub const ViewClip = struct {
    Rect: ClipRect,
    /// the entity with the ClipComponent, which a batch keys its shared copy by
    Owner: Entity.Type,
};

/// One entity a view shows, with the canvas that places it for an overlay entity (null in the game layer,
/// whose transforms are already world space), and the clip region it is inside, if any
pub const ViewShape = struct {
    Entity: Entity,
    Canvas: ?CanvasTransform,
    Clip: ?ViewClip = null,
};

/// An overlay scene's canvas in front of this camera: its entities' transforms are in canvas units and this
/// is what places them in the world
pub fn SceneCanvas(scene: Scene, camera_view: CameraView) CanvasTransform {
    const scene_component = scene.GetComponent(SceneComponent).?;
    return OverlayCanvas.ComputeCanvasTransform(
        camera_view.Pose,
        camera_view.TanHalfFov,
        camera_view.TargetHeight,
        scene_component.GetPixelsPerUnit(camera_view.TargetHeight, camera_view.DisplayScale),
    );
}

/// Every entity matching `query` that this view shows, each with its canvas: the renderer draws this list and
/// picking tests it, so the two always agree on what a view contains. Overlay scenes come first, each canvas
/// worked out once for its whole scene, then the game layer. Overlay scenes that are gone, or aren't overlays,
/// are left out. Only valid for the frame it was built in
pub fn GatherViewShapes(
    frame_allocator: std.mem.Allocator,
    world: *WorldManager,
    camera_view: CameraView,
    view_scenes: ViewScenes,
    comptime query: GroupQuery,
) !std.ArrayList(ViewShape) {
    //folded away by a collapsed layout item: neither drawn nor clickable
    const hidden = GroupQuery{ .Component = LayoutHiddenTag };
    const overlay_shapes = GroupQuery{ .And = &[_]GroupQuery{ query, .{ .Component = OverlayLayerTag } } };
    const game_shapes = GroupQuery{ .And = &[_]GroupQuery{ query, .{ .Component = GameLayerTag } } };
    const overlay_query = GroupQuery{ .Not = .{ .mFirst = &overlay_shapes, .mSecond = &hidden } };
    const game_query = GroupQuery{ .Not = .{ .mFirst = &game_shapes, .mSecond = &hidden } };

    var shapes: std.ArrayList(ViewShape) = .empty;
    var clips = ClipFinder{ .mAllocator = frame_allocator };

    for (view_scenes.Overlays) |scene_id| {
        const scene = world.GetScene(scene_id);
        if (!scene.IsActive() or scene.GetLayer() != .OverlayLayer) continue;

        const canvas = SceneCanvas(scene, camera_view);
        const entity_ids = try scene.GetEntityGroup(frame_allocator, overlay_query);
        try shapes.ensureUnusedCapacity(frame_allocator, entity_ids.items.len);
        for (entity_ids.items) |entity_id| {
            const entity = world.GetEntity(entity_id);
            shapes.appendAssumeCapacity(.{ .Entity = entity, .Canvas = canvas, .Clip = try clips.ClipOf(entity, canvas) });
        }
    }

    const game_ids = switch (view_scenes.Game) {
        .All => try world.GetEntityGroup(frame_allocator, game_query),
        .One => |scene_id| try world.GetScene(scene_id).GetEntityGroup(frame_allocator, game_query),
        .None => return shapes,
    };
    try shapes.ensureUnusedCapacity(frame_allocator, game_ids.items.len);
    for (game_ids.items) |entity_id| {
        const entity = world.GetEntity(entity_id);
        shapes.appendAssumeCapacity(.{ .Entity = entity, .Canvas = null, .Clip = try clips.ClipOf(entity, null) });
    }

    return shapes;
}

/// Works out which clip region each shape is inside, remembering each region's clip for the rest of the gather:
/// a long scrolled list's rows all ask about the same one
const ClipFinder = struct {
    mAllocator: std.mem.Allocator,
    /// each region's clip: its own rectangle cut to the regions it is inside. Null for a region with no
    /// rectangle and nothing around it
    mRegions: std.AutoHashMapUnmanaged(Entity.Type, ?ViewClip) = .empty,

    /// The clip `entity` is cut to: its nearest parent (or further up) with a ClipComponent. Its own isn't one: the
    /// region's own quad is the rectangle it cuts to
    fn ClipOf(self: *ClipFinder, entity: Entity, canvas: ?CanvasTransform) !?ViewClip {
        const region = ClipRegionAbove(entity) orelse return null;
        return try self.RegionClip(region, canvas);
    }

    fn RegionClip(self: *ClipFinder, region: Entity, canvas: ?CanvasTransform) anyerror!?ViewClip {
        if (self.mRegions.get(region.mID)) |known| return known;

        const outer = try self.ClipOf(region, canvas);
        const clip: ?ViewClip = if (RegionRect(region, canvas)) |rect| .{
            .Rect = if (outer) |outer_clip| IntersectClips(rect, outer_clip.Rect) else rect,
            .Owner = region.mID,
        } else outer;

        try self.mRegions.put(self.mAllocator, region.mID, clip);
        return clip;
    }
};

/// The nearest entity above `entity` (its parent, or further up) with a ClipComponent
fn ClipRegionAbove(entity: Entity) ?Entity {
    var current = entity;
    while (current.GetComponent(EntityChildComponent)) |child_component| {
        current = Entity{ .mID = child_component.mParent, .mManager = entity.mManager };
        if (current.HasComponent(ClipComponent)) return current;
    }
    return null;
}

/// A clip region's own rectangle in the world: the size layout gave it, or its quad's if it isn't in a layout, grown
/// by its scale, placed by its transform and then the canvas. Null if it has neither
pub fn RegionRect(region: Entity, canvas: ?CanvasTransform) ?ClipRect {
    const transform = region.GetComponent(TransformComponent) orelse return null;
    const size = if (region.GetComponent(LayoutItemComponent)) |item|
        item.mComputedSize
    else if (region.GetComponent(QuadComponent)) |quad|
        quad.mSize
    else
        return null;

    const world_scale = transform.GetWorldScale();
    var rect = ClipRect{
        .Center = transform.GetWorldPosition(),
        .Rotation = transform.GetWorldRotation(),
        .HalfExtents = .{ .x = size.x * world_scale.x * 0.5, .y = size.y * world_scale.y * 0.5 },
    };
    if (canvas) |c| {
        rect.Center = c.ToWorldPoint(rect.Center);
        rect.Rotation = c.ToWorldRotation(rect.Rotation);
        rect.HalfExtents = rect.HalfExtents.MulScalar(c.Scale);
    }
    return rect;
}

/// A clip region inside another one is cut to both: the overlap of the two rectangles, in the inner one's plane.
/// Worked out exactly for rectangles turned the same way, which is how UI nests; one turned differently keeps the
/// inner rectangle as it is
pub fn IntersectClips(inner: ClipRect, outer: ClipRect) ClipRect {
    if (@abs(inner.Rotation.Dot(outer.Rotation)) < 0.9999) return inner;

    const offset = outer.Center.SubVec(inner.Center).InvQuatRotate(inner.Rotation);
    const low = Vec2(f32){
        .x = @max(-inner.HalfExtents.x, offset.x - outer.HalfExtents.x),
        .y = @max(-inner.HalfExtents.y, offset.y - outer.HalfExtents.y),
    };
    const high = Vec2(f32){
        .x = @min(inner.HalfExtents.x, offset.x + outer.HalfExtents.x),
        .y = @min(inner.HalfExtents.y, offset.y + outer.HalfExtents.y),
    };
    //no overlap at all leaves an empty rectangle, which everything is outside of
    const local_center = Vec3(f32){ .x = (low.x + high.x) * 0.5, .y = (low.y + high.y) * 0.5, .z = 0 };
    return .{
        .Center = inner.Center.AddVec(local_center.QuatRotate(inner.Rotation)),
        .Rotation = inner.Rotation,
        .HalfExtents = .{ .x = @max((high.x - low.x) * 0.5, 0), .y = @max((high.y - low.y) * 0.5, 0) },
    };
}

/// Whether a point is inside a clip region's rectangle, through any depth: the same test the renderer cuts with
pub fn ClipContains(clip: ClipRect, point: Vec3(f32)) bool {
    return SDFFunctions.sdClipPrism(point, clip.Center, clip.Rotation, clip.HalfExtents) <= 0;
}

/// Whether all of `box` is outside the clip, so none of it is drawn and it doesn't need sending at all. Compares the
/// box's reach across the clip's plane with the clip's rectangle, which never says outside for a box that isn't
pub fn OutsideClip(box: Box, clip: ClipRect) bool {
    const center = box.Center.SubVec(clip.Center).InvQuatRotate(clip.Rotation);
    //the box's own axes, as seen in the clip's space
    const axis_x = (Vec3(f32){ .x = 1, .y = 0, .z = 0 }).QuatRotate(box.Rotation).InvQuatRotate(clip.Rotation);
    const axis_y = (Vec3(f32){ .x = 0, .y = 1, .z = 0 }).QuatRotate(box.Rotation).InvQuatRotate(clip.Rotation);
    const axis_z = (Vec3(f32){ .x = 0, .y = 0, .z = 1 }).QuatRotate(box.Rotation).InvQuatRotate(clip.Rotation);
    const half = box.HalfExtents;
    const reach_x = @abs(axis_x.x) * half.x + @abs(axis_y.x) * half.y + @abs(axis_z.x) * half.z;
    const reach_y = @abs(axis_x.y) * half.x + @abs(axis_y.y) * half.y + @abs(axis_z.y) * half.z;
    return @abs(center.x) - reach_x > clip.HalfExtents.x or @abs(center.y) - reach_y > clip.HalfExtents.y;
}

/// The quad's own size grown by its scale (and everything above it in the hierarchy), placed by the
/// canvas for an overlay quad. Thickness stays THICKNESS_2D in world units either way.
pub fn QuadBox(transform: *const TransformComponent, quad: *const QuadComponent, canvas: ?CanvasTransform) Box {
    const world_scale = transform.GetWorldScale();
    var center = transform.GetWorldPosition();
    var rotation = transform.GetWorldRotation();
    var half_x = quad.mSize.x * world_scale.x * 0.5;
    var half_y = quad.mSize.y * world_scale.y * 0.5;

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
    const radii = quad.mCornerRadii.MulScalar(size_scale);

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
        .BorderWidth = std.math.clamp(quad.mBorderWidth * size_scale, 0, most),
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
