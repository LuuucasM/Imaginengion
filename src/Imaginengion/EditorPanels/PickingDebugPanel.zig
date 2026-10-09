//! The Picking Debug panel, in the editor's own UI: a floating window showing what the mouse is over as picking sees
//! it, in folding sections that start folded, since it is a lot of text: the window, the pointer system's state and the
//! last pointer or UI event, the view and ray under the mouse, what a click there would select and the collider under
//! it, and the canvas point of each overlay scene the view shows. Each open section's lines are worked out every frame
//! and put on its labels (Widgets.SyncLines); a folded one isn't worked out at all. It reads the view rects the panels
//! recorded last frame, which is what was on screen, the same as next frame's input will
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const EditorProgram = @import("../Programs/EditorProgram.zig");
const ViewportPanel = @import("../Imgui/ViewportPanel.zig");
const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");
const RayCast = @import("../Physics/RayCast.zig");
const CameraView = @import("../Renderer/Renderer.zig").CameraView;
const UIEvent = @import("../Events/UIEventData.zig").EventT;
const PointerEvent = @import("../Events/PointerEventData.zig").EventT;
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntityNameComponent = EntityComponents.NameComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const PlayerNameComponent = @import("../ECSComponents/PComponents.zig").NameComponent;
const SceneNameComponent = @import("../ECSComponents/SComponents.zig").NameComponent;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;

const PickingDebugPanel = @This();

/// Where the window opens, from the middle of the editor UI, and how big it is
const AT = Vec2(f32){ .x = -250, .y = 0 };
const SIZE = Vec2(f32){ .x = 460, .y = 480 };

/// A folding section: its content, and the column of lines in it
pub const Section = struct {
    Content: Entity,
    Lines: Entity,

    fn IsOpen(self: Section) bool {
        return !self.Content.GetComponent(LayoutItemComponent).?.mCollapsed;
    }
};

/// The lines a section is given this frame
const Lines = struct {
    mAllocator: std.mem.Allocator,
    mLines: std.ArrayList([]const u8) = .empty,

    fn Add(self: *Lines, comptime format: []const u8, args: anytype) !void {
        try self.mLines.append(self.mAllocator, try std.fmt.allocPrint(self.mAllocator, format, args));
    }
};

mWindow: Entity = .uninit,
mWindowSection: Section = undefined,
mPointer: Section = undefined,
mView: Section = undefined,
mCasts: Section = undefined,
mOverlays: Section = undefined,
/// The last thing a mouse button or the UI did, to see events arrive
mLastEvent: [128]u8 = undefined,
mLastEventLen: usize = 0,

/// Builds the window, closed, at the top of `scene`
pub fn Build(engine_context: *EngineContext, scene: Scene, options: Widgets.Options) !PickingDebugPanel {
    const zone = Tracy.ZoneInit("PickingDebugPanel::Build", @src());
    defer zone.Deinit();
    const window = try Widgets.FloatingWindow(engine_context, scene, "Picking Debug", SIZE, AT, options);
    var self = PickingDebugPanel{ .mWindow = window.Window };
    self.mWindowSection = try NewSection(engine_context, window.Content, "Window", options);
    self.mPointer = try NewSection(engine_context, window.Content, "Pointer", options);
    self.mView = try NewSection(engine_context, window.Content, "Under the mouse", options);
    self.mCasts = try NewSection(engine_context, window.Content, "Ray casts", options);
    self.mOverlays = try NewSection(engine_context, window.Content, "Overlays", options);
    try WidgetActions.CloseWindow(engine_context, self.mWindow);
    return self;
}

fn NewSection(engine_context: *EngineContext, content: Entity, title: []const u8, options: Widgets.Options) !Section {
    const section = try Widgets.CollapsingHeader(engine_context, .{ .Entity = content }, title, false, options);
    return .{ .Content = section.Content.?, .Lines = try Widgets.Lines(engine_context, .{ .Entity = section.Content.? }) };
}

pub fn IsOpen(self: PickingDebugPanel) bool {
    return WidgetActions.IsWindowOpen(self.mWindow);
}

/// Opens the window in front of the others, or closes it
pub fn Toggle(self: PickingDebugPanel, engine_context: *EngineContext) !void {
    if (self.IsOpen()) {
        try WidgetActions.CloseWindow(engine_context, self.mWindow);
    } else {
        try WidgetActions.OpenWindow(engine_context, self.mWindow);
    }
}

/// Once a frame, before layout, while it is open: each open section's lines
pub fn Update(self: *const PickingDebugPanel, engine_context: *EngineContext, viewport_panel: *const ViewportPanel, editor_program: *const EditorProgram) !void {
    const zone = Tracy.ZoneInit("PickingDebugPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) return;
    const frame_allocator = engine_context.FrameAllocator();
    const mouse_pos = engine_context.mInputManager.GetMousePosition();

    if (self.mWindowSection.IsOpen()) {
        var lines = Lines{ .mAllocator = frame_allocator };
        try lines.Add("Mouse (window): {d:.1}, {d:.1}", .{ mouse_pos.x, mouse_pos.y });
        try lines.Add("Pixel density: {d:.2}   Display scale: {d:.2}", .{ engine_context.mAppWindow.GetPixelDensity(), engine_context.mAppWindow.GetDisplayScale() });
        try lines.Add("Views drawn: Viewport {d}, Play {d} (hovered: {})", .{ editor_program.mViewportQuads.items.len, viewport_panel.mPlayRects.items.len, viewport_panel.mIsHoveredPlay });
        try Widgets.SyncLines(engine_context, self.mWindowSection.Lines, lines.mLines.items);
    }

    if (self.mPointer.IsOpen()) {
        var lines = Lines{ .mAllocator = frame_allocator };
        try self.PointerLines(engine_context, &lines);
        try Widgets.SyncLines(engine_context, self.mPointer.Lines, lines.mLines.items);
    }

    //the rest all need the view under the mouse, so it is only looked for when one of them is open
    if (!self.mView.IsOpen() and !self.mCasts.IsOpen() and !self.mOverlays.IsOpen()) return;
    var view_lines = Lines{ .mAllocator = frame_allocator };
    var cast_lines = Lines{ .mAllocator = frame_allocator };
    var overlay_lines = Lines{ .mAllocator = frame_allocator };
    try self.ViewLines(engine_context, editor_program, mouse_pos, &view_lines, &cast_lines, &overlay_lines);
    if (self.mView.IsOpen()) try Widgets.SyncLines(engine_context, self.mView.Lines, view_lines.mLines.items);
    if (self.mCasts.IsOpen()) try Widgets.SyncLines(engine_context, self.mCasts.Lines, cast_lines.mLines.items);
    if (self.mOverlays.IsOpen()) try Widgets.SyncLines(engine_context, self.mOverlays.Lines, overlay_lines.mLines.items);
}

/// The pointer system's state: only a running game's views have one, the editor camera's view is for selecting
fn PointerLines(self: *const PickingDebugPanel, engine_context: *EngineContext, lines: *Lines) !void {
    const pointer_system = &engine_context.mPointerSystem;
    try ChainLine(lines, "Pointer over", pointer_system.mHovered.items);
    try ChainLine(lines, "Left button holding", pointer_system.mHeld.get(.BUTTON_LEFT).mChain.items);
    try lines.Add("Carrying: {s}", .{if (pointer_system.Carrying()) |source| EntityName(source) else "nothing"});

    var popup_names: std.ArrayList(u8) = .empty;
    for (engine_context.mUIManager.mPopupSystem.OpenPopups(), 0..) |open, i| {
        if (i > 0) try popup_names.appendSlice(lines.mAllocator, " > ");
        try popup_names.appendSlice(lines.mAllocator, if (open.mPopup.IsActive()) EntityName(open.mPopup) else "<gone>");
    }
    try lines.Add("Popups open: {s}", .{if (popup_names.items.len > 0) popup_names.items else "none"});

    if (engine_context.mUIManager.mFocusSystem.Focused()) |focused| {
        try lines.Add("Keyboard: typing into '{s}', caret at byte {d}", .{ EntityName(focused), engine_context.mUIManager.mFocusSystem.Caret() });
    } else {
        try lines.Add("Keyboard: nothing has it", .{});
    }
    try lines.Add("Last event: {s}", .{if (self.mLastEventLen > 0) self.mLastEvent[0..self.mLastEventLen] else "none yet"});
}

/// The view under the mouse, the same one a click looks for (EditorProgram.ViewUnder), and from it the ray casts and
/// the overlays' canvas points. With no view, each section says so
fn ViewLines(_: *const PickingDebugPanel, engine_context: *EngineContext, editor_program: *const EditorProgram, mouse_pos: Vec2(f32), view_lines: *Lines, cast_lines: *Lines, overlay_lines: *Lines) !void {
    const view = try editor_program.ViewUnder(engine_context, mouse_pos) orelse {
        for ([_]*Lines{ view_lines, cast_lines, overlay_lines }) |lines| try lines.Add("No view under the mouse", .{});
        return;
    };
    //the camera may have stopped being drawable since the views were drawn
    const render_view = view.Camera.GetRenderView() orelse {
        for ([_]*Lines{ view_lines, cast_lines, overlay_lines }) |lines| try lines.Add("Camera is no longer drawable", .{});
        return;
    };
    const target_size = Vec2(f32){ .x = @floatFromInt(render_view.mViewpoint.mViewportWidth), .y = @floatFromInt(render_view.mViewpoint.mViewportHeight) };

    const camera_name = if (view.Camera.GetComponent(PlayerNameComponent)) |name_component| name_component.mName.items else "<unnamed>";
    try view_lines.Add("Camera: {s}", .{camera_name});
    try view_lines.Add("World: {s}", .{@tagName(view.World)});
    try view_lines.Add("Target pixel: {d:.1}, {d:.1} of {d:.0} x {d:.0}", .{ view.Pixel.x, view.Pixel.y, target_size.x, target_size.y });

    //the same ray and camera view a click uses, which are the ones the renderer drew this view with
    const camera_view = CameraView.FromViewpoint(render_view.mTransform, render_view.mViewpoint, engine_context.mAppWindow.GetDisplayScale());
    const ray = CameraView.PixelRay(render_view.mTransform, render_view.mViewpoint, view.Pixel);
    try view_lines.Add("Ray origin: {d:.3}, {d:.3}, {d:.3}", .{ ray.Origin.x, ray.Origin.y, ray.Origin.z });
    try view_lines.Add("Ray dir: {d:.4}, {d:.4}, {d:.4}", .{ ray.Dir.x, ray.Dir.y, ray.Dir.z });
    //what the ray at the exact center reads, to compare against while hovering the middle
    const center = CameraView.PixelRay(render_view.mTransform, render_view.mViewpoint, target_size.MulScalar(0.5));
    try view_lines.Add("Camera forward: {d:.4}, {d:.4}, {d:.4}", .{ center.Dir.x, center.Dir.y, center.Dir.z });

    const world = switch (view.World) {
        .Game => &engine_context.mGameWorld,
        .Editor => &engine_context.mEditorWorld,
        .Simulate => &engine_context.mSimulateWorld,
    };
    //the overlays this view shows, as the renderer drew it
    const view_scenes = try editor_program.ViewScenesFor(engine_context.FrameAllocator(), view.Camera, world);

    //exactly what a left click here would do
    try cast_lines.Add("A click here selects:", .{});
    if (try RayCast.CastRay(engine_context, world, ray, camera_view, view_scenes, .{})) |hit| {
        try cast_lines.Add("    {s}", .{EntityName(hit.Entity.GetMainObject())});
        try HitLines(cast_lines, hit);
    } else {
        try cast_lines.Add("    nothing (it clears the selection)", .{});
    }
    try cast_lines.Add("Collider under the mouse:", .{});
    if (try RayCast.CastRay(engine_context, world, ray, camera_view, view_scenes, .{ .Targets = .Colliders })) |hit| {
        try HitLines(cast_lines, hit);
    } else {
        try cast_lines.Add("    none", .{});
    }

    //the canvas point under the mouse for each overlay scene this view shows, placed the same way the renderer placed
    //it (see ShapeGeometry.WorldCanvas): the world's one screen space, which they all share
    const pixels_per_unit = world.OverlayPixelsPerUnit(camera_view.TargetHeight, camera_view.DisplayScale);
    const canvas = ShapeGeometry.WorldCanvas(world, camera_view);
    for (view_scenes.Overlays) |scene_id| {
        const scene = world.GetScene(scene_id);
        const scene_name = if (scene.GetComponent(SceneNameComponent)) |name_component| name_component.mName.items else "<unnamed>";
        try overlay_lines.Add("Overlay '{s}' ({s}, {d:.2} px per unit)", .{ scene_name, @tagName(world.mOverlayScaleMode), pixels_per_unit });
        if (canvas.RayToCanvasPoint(ray)) |point| {
            try overlay_lines.Add("    Canvas point: {d:.1}, {d:.1}", .{ point.x, point.y });
        } else {
            try overlay_lines.Add("    Canvas point: none", .{});
        }
    }
    if (view_scenes.Overlays.len == 0) try overlay_lines.Add("No overlay scenes in this view", .{});
}

/// The shape that was hit and where, under a heading line
fn HitLines(lines: *Lines, hit: RayCast.RayHit) !void {
    try lines.Add("    hit {s} on '{s}' ({s})", .{ @tagName(hit.Kind), EntityName(hit.Entity), @tagName(hit.Layer) });
    try lines.Add("    distance {d:.3}", .{hit.T});
    try lines.Add("    position {d:.3}, {d:.3}, {d:.3}", .{ hit.Position.x, hit.Position.y, hit.Position.z });
    try lines.Add("    normal {d:.3}, {d:.3}, {d:.3}", .{ hit.Normal.x, hit.Normal.y, hit.Normal.z });
}

/// The entities of a pointer chain, the one under the pointer first and then what it is inside
fn ChainLine(lines: *Lines, label: []const u8, chain: []const Entity) !void {
    var names: std.ArrayList(u8) = .empty;
    for (chain, 0..) |entity, i| {
        if (i > 0) try names.appendSlice(lines.mAllocator, " < ");
        try names.appendSlice(lines.mAllocator, if (entity.IsActive()) EntityName(entity) else "<gone>");
    }
    try lines.Add("{s}: {s}", .{ label, if (names.items.len > 0) names.items else "nothing" });
}

fn EntityName(entity: Entity) []const u8 {
    const name_component = entity.GetComponent(EntityNameComponent) orelse return "<unnamed>";
    return if (name_component.mName.items.len > 0) name_component.mName.items else "<unnamed>";
}

/// Remembers the last press, release or click to show. Enter and exit aren't kept: they'd bury the clicks, and
/// what is hovered is shown as it is
pub fn OnPointerEvent(self: *PickingDebugPanel, event: PointerEvent) void {
    const text = switch (event) {
        .PointerPressed => |e| std.fmt.bufPrint(&self.mLastEvent, "{s} pressed on '{s}'", .{ @tagName(e.mButton), EntityName(e.mEntity) }),
        .PointerReleased => |e| std.fmt.bufPrint(&self.mLastEvent, "{s} released from '{s}'", .{ @tagName(e.mButton), EntityName(e.mEntity) }),
        .PointerClicked => |e| std.fmt.bufPrint(&self.mLastEvent, "{s} clicked '{s}' x{d}", .{ @tagName(e.mButton), EntityName(e.mEntity), e.mClicks }),
        .PointerDragStart => |e| std.fmt.bufPrint(&self.mLastEvent, "{s} started dragging '{s}'", .{ @tagName(e.mButton), EntityName(e.mEntity) }),
        .PointerDrag => |e| std.fmt.bufPrint(&self.mLastEvent, "{s} dragging '{s}', {d:.1}, {d:.1}, {d:.1} so far", .{ @tagName(e.mButton), EntityName(e.mEntity), e.mTotal.x, e.mTotal.y, e.mTotal.z }),
        .PointerDragEnd => |e| std.fmt.bufPrint(&self.mLastEvent, "{s} dragged '{s}' {d:.1}, {d:.1}, {d:.1}", .{ @tagName(e.mButton), EntityName(e.mEntity), e.mTotal.x, e.mTotal.y, e.mTotal.z }),
        .PointerDropped => |e| std.fmt.bufPrint(&self.mLastEvent, "dropped '{s}' on '{s}'", .{ EntityName(e.mSource), EntityName(e.mEntity) }),
        .PointerEnter, .PointerExit, .Default => return,
    } catch return;
    self.mLastEventLen = text.len;
}

/// The same for the UI's events: typing and popups
pub fn OnUIEvent(self: *PickingDebugPanel, event: UIEvent) void {
    const text = switch (event) {
        //one per entity in the chain: only the target's own, so it isn't always its top parent's
        .FocusGained => |e| if (Same(e.mEntity, e.mTarget)) std.fmt.bufPrint(&self.mLastEvent, "'{s}' got the keyboard", .{EntityName(e.mTarget)}) else return,
        .FocusLost => |e| if (Same(e.mEntity, e.mTarget)) std.fmt.bufPrint(&self.mLastEvent, "'{s}' lost the keyboard", .{EntityName(e.mTarget)}) else return,
        .TextChanged => |e| if (Same(e.mEntity, e.mTarget)) std.fmt.bufPrint(&self.mLastEvent, "'{s}' text changed", .{EntityName(e.mTarget)}) else return,
        .TextSubmitted => |e| if (Same(e.mEntity, e.mTarget)) std.fmt.bufPrint(&self.mLastEvent, "'{s}' text submitted", .{EntityName(e.mTarget)}) else return,
        .PopupOpened => |e| if (Same(e.mEntity, e.mTarget)) std.fmt.bufPrint(&self.mLastEvent, "popup '{s}' opened", .{EntityName(e.mTarget)}) else return,
        .PopupClosed => |e| if (Same(e.mEntity, e.mTarget)) std.fmt.bufPrint(&self.mLastEvent, "popup '{s}' closed", .{EntityName(e.mTarget)}) else return,
        .ValueChanged => |e| if (Same(e.mEntity, e.mTarget)) std.fmt.bufPrint(&self.mLastEvent, "'{s}' value changed", .{EntityName(e.mTarget)}) else return,
        .DestroyUIElement, .Default => return,
    } catch return;
    self.mLastEventLen = text.len;
}

fn Same(a: Entity, b: Entity) bool {
    return a.mID == b.mID and a.mManager == b.mManager;
}
