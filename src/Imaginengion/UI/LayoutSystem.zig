//! The layout pass: lays out every layout tree that has been marked dirty (LayoutDirtyTag), and writes the
//! results into the components that already exist. A tree is an entity with a LayoutItemComponent or a
//! LayoutComponent, and below it every child that has one of those too, for as long as each parent is a container
//! (has a LayoutComponent). Entities without either are left wherever their transform puts them, and anything
//! under one starts a tree of its own.
//!
//! Written back for each element:
//!   - its translation's x and y, when layout decided where it goes. Never z: how things stack in depth is up
//!     to whoever places them. Only written when it changed, so an unchanged tree doesn't dirty any transforms
//!   - its own QuadComponent's size, as its background. A quad is only ever written, never read as something to
//!     fit to: layout reading back its own output would keep elements at the largest size they have ever been
//!   - its own TextComponent's bounds, for a leaf, whose text is what it fits to
//!   - LayoutItemComponent.mComputedSize
//!
//! Runs before the transform pass each frame, which picks up the translations it set.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const CameraView = @import("../Renderer/Renderer.zig").CameraView;
const Layout = @import("Layout.zig");
const TextLayout = @import("../Renderer/TextLayout.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const LayoutComponent = EntityComponents.LayoutComponent;
const UIManager = @import("UIManager.zig");
const UIComponents = @import("../ECSComponents/UIComponents.zig");
const ScrollComponent = UIComponents.ScrollComponent;
const ScrollStateComponent = UIComponents.ScrollStateComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const LayoutDirtyTag = EntityComponents.LayoutDirtyTag;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const SceneComponent = @import("../ECSComponents/SComponents.zig").SceneComponent;
const TextAsset = @import("../ECSComponents/AComponents.zig").TextAsset;
const EManager = @import("../ECSManagers/EManager.zig");
const EventResult = @import("../Events/EventManager.zig").EventResult;

/// Lays out every tree in `world` that has a dirty entity in it, each once however many of its entities are dirty
pub fn UpdateLayouts(world: *WorldManager, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("LayoutSystem::UpdateLayouts", @src());
    defer zone.Deinit();

    const frame_allocator = engine_context.FrameAllocator();
    const dirty_ids = try world.GetEntityGroup(frame_allocator, .{ .Component = LayoutDirtyTag });

    var roots: std.ArrayList(Entity.Type) = .empty;
    for (dirty_ids.items) |entity_id| {
        const entity = world.GetEntity(entity_id);
        if (!IsInLayout(entity)) {
            //nothing of it to lay out any more, e.g. its layout components were removed after it was tagged
            try entity.ClearLayoutDirty(engine_context);
            continue;
        }
        const root = FindRoot(entity);
        if (std.mem.indexOfScalar(Entity.Type, roots.items, root.mID) == null) try roots.append(frame_allocator, root.mID);
    }

    for (roots.items) |root_id| {
        try LayoutTree(world.GetEntity(root_id), engine_context);
    }
}

/// Asks for every layout tree in `scene` to be laid out again, e.g. because the screen it fits into changed. Tagging
/// each tree's root is enough, one tag lays out its whole tree
pub fn MarkSceneDirty(scene: Scene, engine_context: *EngineContext) !void {
    const entity_ids = try scene.GetEntityGroup(engine_context.FrameAllocator(), .{ .Or = &.{
        .{ .Component = LayoutItemComponent },
        .{ .Component = LayoutComponent },
    } });
    for (entity_ids.items) |entity_id| {
        const entity = scene.GetEntity(entity_id);
        if (FindRoot(entity).mID == entity.mID) try entity.MarkLayoutDirty(engine_context);
    }
}

/// Each overlay scene in `overlay_scenes` records the screen this view draws it on, in its own canvas units (the
/// view's size in pixels over the world's pixels per unit): what its layout roots fit into. When that changes,
/// because the view was resized or the world's scale mode changed, its trees are laid out again. Called by the
/// renderer as it draws each view, so a scene drawn by several views of different sizes fits the last one drawn
pub fn RecordViewArea(world: *WorldManager, overlay_scenes: []const Scene.Type, camera_view: CameraView, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("LayoutSystem::RecordViewArea", @src());
    defer zone.Deinit();
    //every overlay scene of the world is on the one screen space, so they all fit into the same area
    const pixels_per_unit = world.OverlayPixelsPerUnit(camera_view.TargetHeight, camera_view.DisplayScale);
    //a view with no size has nothing to fit into, and would divide by nothing
    if (pixels_per_unit <= 0) return;
    const area = Vec2(f32){ .x = camera_view.TargetWidth / pixels_per_unit, .y = camera_view.TargetHeight / pixels_per_unit };
    for (overlay_scenes) |scene_id| {
        const scene = world.GetScene(scene_id);
        if (!scene.IsActive() or scene.GetLayer() != .OverlayLayer) continue;

        const scene_component = scene.GetComponent(SceneComponent).?;

        if (scene_component.mLayoutArea) |old_area| {
            if (old_area.x == area.x and old_area.y == area.y) continue;
        }
        scene_component.mLayoutArea = area;
        try MarkSceneDirty(scene, engine_context);
    }
}

/// Whether layout sizes and places this entity: it has a LayoutItemComponent, or it is a container, which is laid
/// out as if it had the default item
pub fn IsInLayout(entity: Entity) bool {
    return entity.HasComponent(LayoutItemComponent) or entity.HasComponent(LayoutComponent);
}

/// The top of the layout tree `entity` is in: up through its parents for as long as each one is a container
pub fn FindRoot(entity: Entity) Entity {
    var current = entity;
    while (current.GetComponent(EntityChildComponent)) |child_component| {
        const parent = Entity{ .mID = child_component.mParent, .mManager = entity.mManager };
        if (!parent.HasComponent(LayoutComponent)) break;
        current = parent;
    }
    return current;
}

/// Whether layout decides where this entity goes, so a translation set by hand is put back: a flow item in a
/// container, or anything anchored in a container or to an overlay's screen. A root that isn't anchored, or a panel
/// in the world, is placed by its own transform
pub fn IsPlacedByLayout(entity: Entity) bool {
    if (!IsInLayout(entity)) return false;
    if (ParentContainer(entity) != null) return true;
    const item = entity.GetComponent(LayoutItemComponent) orelse return false;
    return item.mPlacement == .Anchored and entity.GetLayer() == .OverlayLayer;
}

/// The entity's parent, if it is a container, which makes the entity part of the parent's tree
fn ParentContainer(entity: Entity) ?Entity {
    const child_component = entity.GetComponent(EntityChildComponent) orelse return null;
    const parent = Entity{ .mID = child_component.mParent, .mManager = entity.mManager };
    if (!parent.IsActive() or !parent.HasComponent(LayoutComponent)) return null;
    return parent;
}

/// Listens to the entity ECS's end of frame events, which run when a queued removal or delete actually happens and
/// before it does, so everything is still readable. Tagging when the removal is only asked for could be too early:
/// a layout pass later that frame would still see the component, lay the tree out with it and clear the tag, and
/// then nothing would be left to lay it out without it.
/// There is no reparenting yet. When there is, it has to tag the tree the entity leaves and the one it joins.
pub fn OnEntityECSEvent(ctx: *anyopaque, engine_context: *EngineContext, event: *const EManager.ECSManagerT.ECSEventDataT.EventT) anyerror!EventResult {
    const entity_manager: *EManager = @ptrCast(@alignCast(ctx));
    const world: *WorldManager = @fieldParentPtr("mEManager", entity_manager);

    switch (event.*) {
        .RemoveComponent => |removal| {
            const removes_container = removal.mComponentInd == EManager.ECSManagerT.ComponentInd(LayoutComponent);
            const affects_layout = removes_container or
                removal.mComponentInd == EManager.ECSManagerT.ComponentInd(LayoutItemComponent) or
                removal.mComponentInd == EManager.ECSManagerT.ComponentInd(TextComponent);
            if (!affects_layout) return .Continue;

            const entity = world.GetEntity(removal.mEntityID);
            if (!entity.IsActive()) return .Continue;
            //the tree it leaves, or fits differently in without its text
            if (ParentContainer(entity)) |parent| try parent.MarkLayoutDirty(engine_context);
            //it may still be in a layout through its other component; if not, its tag is just cleared
            try entity.MarkLayoutDirty(engine_context);
            //a container's children are left as the roots of trees of their own
            if (removes_container) {
                var children = entity.GetIterator(.Child);
                while (children.next()) |child| {
                    if (IsInLayout(child)) try child.MarkLayoutDirty(engine_context);
                }
            }
        },
        .DestroyEntity => |destroy| {
            const entity = world.GetEntity(destroy.mEntityID);
            //the destroy can be queued twice, and a parent destroyed first takes its whole tree with it
            if (!entity.IsActive() or !IsInLayout(entity)) return .Continue;
            if (ParentContainer(entity)) |parent| try parent.MarkLayoutDirty(engine_context);
        },
        .Default => {},
    }
    return .Continue;
}

/// Lays out the tree under `root` and clears the dirty tag from all of it. An overlay tree whose scene hasn't been
/// drawn yet has no screen to fit into, so it keeps its tags and waits for the frame after its first draw
pub fn LayoutTree(root: Entity, engine_context: *EngineContext) !void {
    const frame_allocator = engine_context.FrameAllocator();

    const root_area: ?Vec2(f32) = switch (root.GetLayer()) {
        //nothing around a panel in the world: it is sized, and placed by its own transform
        .GameLayer => null,
        .OverlayLayer => blk: {
            const scene = root.GetComponent(EntitySceneComponent).?.mScene;
            break :blk scene.GetComponent(SceneComponent).?.mLayoutArea orelse return;
        },
    };

    var tree: Tree = .{};
    try tree.Add(root, null, engine_context, frame_allocator);

    const results = try Layout.Solve(frame_allocator, tree.mNodes.items, 0, root_area);
    for (tree.mEntities.items, tree.mTextCenters.items, results) |entity, text_center, result| {
        try WriteBack(entity, text_center, result, engine_context);
        try entity.ClearLayoutDirty(engine_context);
    }

    //hidden if it is collapsed, or is under something collapsed from an outer tree
    const parent_hidden = if (root.GetComponent(EntityChildComponent)) |child_component|
        (Entity{ .mID = child_component.mParent, .mManager = root.mManager }).HasComponent(LayoutHiddenTag)
    else
        false;
    try ApplyHidden(root, parent_hidden or IsCollapsed(root), engine_context);
}

/// Hides or shows `entity` and everything under it: layout elements, and anything placed by hand under them too.
/// A collapsed element further down keeps its own part hidden when an outer one is expanded
fn ApplyHidden(entity: Entity, hidden: bool, engine_context: *EngineContext) !void {
    if (hidden and !entity.HasComponent(LayoutHiddenTag)) {
        _ = try entity.AddComponent(engine_context, LayoutHiddenTag{});
    } else if (!hidden and entity.HasComponent(LayoutHiddenTag)) {
        //zero sized, so the removal moves no storage
        try entity.RemoveComponentSync(engine_context, LayoutHiddenTag);
    }

    var children = entity.GetIterator(.Child);
    while (children.next()) |child| {
        try ApplyHidden(child, hidden or IsCollapsed(child), engine_context);
    }
}

fn IsCollapsed(entity: Entity) bool {
    const item = entity.GetComponent(LayoutItemComponent) orelse return false;
    return item.mCollapsed;
}

/// A layout tree's entities as layout nodes, in the same order: node i is entity i, and the root is 0
const Tree = struct {
    mNodes: std.ArrayList(Layout.Node) = .empty,
    mEntities: std.ArrayList(Entity) = .empty,
    /// for a leaf fitting its text, the middle of the text's room relative to where the text is placed
    mTextCenters: std.ArrayList(?Vec2(f32)) = .empty,
    mLastChild: std.ArrayList(?Layout.Index) = .empty,

    /// Adds `entity` as the last child of `parent`, and then everything under it that is in the tree
    fn Add(self: *Tree, entity: Entity, parent: ?Layout.Index, engine_context: *EngineContext, frame_allocator: std.mem.Allocator) anyerror!void {
        var node = if (entity.GetComponent(LayoutItemComponent)) |item| item.ToNode() else (LayoutItemComponent{}).ToNode();
        var text_center: ?Vec2(f32) = null;
        if (entity.GetComponent(LayoutComponent)) |layout| {
            node.Container = layout.ToContainer();
            //a container whose UI element scrolls
            if (UIManager.GetUIComponent(entity, ScrollComponent)) |scroll| {
                node.Container.?.Scroll = scroll.mScroll;
                if (UIManager.GetUIComponent(entity, ScrollStateComponent)) |state| node.Container.?.ScrollOffset = state.mOffset;
            }
        } else if (try MeasureText(entity, engine_context)) |metrics| {
            //a leaf fits its text. A container fits its children, and its own text is left as it is
            node.Content = .{ .Size = metrics.Size() };
            text_center = metrics.Center();
        }

        const index: Layout.Index = @intCast(self.mNodes.items.len);
        try self.mNodes.append(frame_allocator, node);
        try self.mEntities.append(frame_allocator, entity);
        try self.mTextCenters.append(frame_allocator, text_center);
        try self.mLastChild.append(frame_allocator, null);
        if (parent) |parent_index| {
            if (self.mLastChild.items[parent_index]) |last| {
                self.mNodes.items[last].NextSibling = index;
            } else {
                self.mNodes.items[parent_index].FirstChild = index;
            }
            self.mLastChild.items[parent_index] = index;
        }

        if (node.Container == null) return;
        var children = entity.GetIterator(.Child);
        while (children.next()) |child| {
            if (IsInLayout(child)) try self.Add(child, index, engine_context, frame_allocator);
        }
    }
};

/// The room the entity's text takes on one line (or several, where it has line breaks) at its own font size, or
/// null if it has no text to measure. Scale is left out, like everything layout does: it is applied on top
fn MeasureText(entity: Entity, engine_context: *EngineContext) !?TextLayout.Metrics {
    const text = entity.GetComponent(TextComponent) orelse return null;
    if (!text.mTextAssetHandle.IsIDValid()) return null;
    const font = try text.mTextAssetHandle.GetAsset(engine_context, TextAsset);
    return TextLayout.Measure(TextAsset, text.mText.items, font, text.mFontSize, 0);
}

fn WriteBack(entity: Entity, text_center: ?Vec2(f32), result: Layout.Result, engine_context: *EngineContext) !void {
    if (entity.GetComponent(LayoutItemComponent)) |item| item.mComputedSize = result.Size;
    //how far it scrolled, kept in range, and how far it can
    if (UIManager.GetUIComponent(entity, ScrollStateComponent)) |state| {
        state.mOffset = result.ScrollOffset;
        state.mContentSize = result.ContentSize;
    }

    //the element's background
    if (entity.GetComponent(QuadComponent)) |quad| quad.mSize = result.Size;

    //text runs from its bounds' left edge, so even bounds put its room across the element. Its room is then moved
    //to the element's middle, rather than its first line's baseline
    var text_offset: Vec2(f32) = .{ .x = 0, .y = 0 };
    if (text_center) |center| {
        const text = entity.GetComponent(TextComponent).?;
        text.mBounds = .{ .x = result.Size.x / 2, .y = result.Size.x / 2 };
        text_offset.y = center.y;
    }

    if (!result.Placed) return;
    const transform = entity.GetComponent(TransformComponent) orelse return;
    const translation = transform.GetTranslation();
    const x = result.Center.x - text_offset.x;
    const y = result.Center.y - text_offset.y;
    if (translation.x == x and translation.y == y) return;
    //not SetTranslation: that would take this for a hand-set translation and ask for the tree to be laid out again,
    //every pass
    transform._SetLocalUntagged(.{ .x = x, .y = y, .z = translation.z }, transform.GetRotation(), transform.GetScale());
    try entity.MarkTransformDirty(engine_context);
}
