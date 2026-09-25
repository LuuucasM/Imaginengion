const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ViewportPanel = @import("ViewportPanel.zig");
const CameraRay = @import("../Math/CameraRay.zig");
const OverlayCanvas = @import("../Math/OverlayCanvas.zig");
const PlayerNameComponent = @import("../ECSComponents/PComponents.zig").NameComponent;
const SceneComponents = @import("../ECSComponents/SComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const SceneNameComponent = SceneComponents.NameComponent;
const PickingDebugPanel = @This();

_P_Open: bool = false,

/// What the mouse is over, as picking will see it: this reads the view rects the panels recorded
/// last frame, which is what was on screen, the same as next frame's input will.
pub fn OnImguiRender(self: PickingDebugPanel, engine_context: *EngineContext, viewport_panel: *const ViewportPanel) !void {
    const zone = Tracy.ZoneInit("PickingDebugPanel::OnImguiRender", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;
    _ = imgui.igBegin("Picking Debug", null, 0);
    defer imgui.igEnd();

    const frame_allocator = engine_context.FrameAllocator();

    const mouse_pos = engine_context.mInputManager.GetMousePosition();
    try Text(frame_allocator, "Mouse (window): {d:.1}, {d:.1}", .{ mouse_pos.x, mouse_pos.y });
    try Text(frame_allocator, "Pixel density: {d:.2}   Display scale: {d:.2}", .{ engine_context.mAppWindow.GetPixelDensity(), engine_context.mAppWindow.GetDisplayScale() });
    try Text(frame_allocator, "Views drawn: Viewport {d} (hovered: {}), Play {d} (hovered: {})", .{
        viewport_panel.mViewportRects.items.len, viewport_panel.mIsHoveredViewport,
        viewport_panel.mPlayRects.items.len,     viewport_panel.mIsHoveredPlay,
    });

    imgui.igSeparator();

    const view_at = viewport_panel.FindViewAt(mouse_pos) orelse {
        try Text(frame_allocator, "No view under the mouse", .{});
        return;
    };
    const view = view_at.View;

    const camera_name = if (view.Camera.GetComponent(PlayerNameComponent)) |name_component| name_component.mName.items else "<unnamed>";
    try Text(frame_allocator, "Panel: {s}", .{@tagName(view_at.Panel)});
    try Text(frame_allocator, "Camera: {s}", .{camera_name});
    try Text(frame_allocator, "World: {s}", .{@tagName(view.World)});
    try Text(frame_allocator, "Target pixel: {d:.1}, {d:.1} of {d:.0} x {d:.0}", .{ view_at.Pixel.x, view_at.Pixel.y, view.Rect.TargetSize.x, view.Rect.TargetSize.y });

    imgui.igSeparator();

    //the camera may have stopped being drawable since the panels recorded it
    const render_view = view.Camera.GetRenderView() orelse {
        try Text(frame_allocator, "Camera is no longer drawable", .{});
        return;
    };
    const pose = CameraRay.Pose{
        .Position = render_view.mTransform.GetWorldPosition(),
        .Rotation = render_view.mTransform.GetWorldRotation(),
    };
    const ray_params = render_view.mViewpoint.GetRayParams();

    const ray = CameraRay.MakeRay(pose, ray_params, view_at.Pixel);
    try Text(frame_allocator, "Ray origin: {d:.3}, {d:.3}, {d:.3}", .{ ray.Origin.x, ray.Origin.y, ray.Origin.z });
    try Text(frame_allocator, "Ray dir: {d:.4}, {d:.4}, {d:.4}", .{ ray.Dir.x, ray.Dir.y, ray.Dir.z });

    //what the ray at the exact center reads, to compare against while hovering the middle
    const center = CameraRay.MakeRay(pose, ray_params, view.Rect.TargetSize.MulScalar(0.5));
    try Text(frame_allocator, "Camera forward: {d:.4}, {d:.4}, {d:.4}", .{ center.Dir.x, center.Dir.y, center.Dir.z });

    imgui.igSeparator();

    //the canvas point under the mouse for each overlay scene, placed the same way the renderer
    //placed it (see Renderer.DrawShape and EditorProgram.BuildCameraView)
    const world = switch (view.World) {
        .Game => &engine_context.mGameWorld,
        .Editor => &engine_context.mEditorWorld,
        .Simulate => &engine_context.mSimulateWorld,
    };
    const tan_half_fov = @tan(render_view.mViewpoint.mPerspectiveFOVRad * 0.5);
    const target_height: f32 = @floatFromInt(render_view.mViewpoint.mViewportHeight);
    const display_scale = engine_context.mAppWindow.GetDisplayScale();

    var overlay_count: usize = 0;
    const scene_ids = try world.GetSceneGroup(frame_allocator, .{ .Component = SceneComponent });
    for (scene_ids.items) |scene_id| {
        const scene = world.GetScene(scene_id);
        const scene_component = scene.GetComponent(SceneComponent).?;
        if (scene_component.mLayerType != .OverlayLayer) continue;
        overlay_count += 1;

        const pixels_per_unit = scene_component.GetPixelsPerUnit(target_height, display_scale);
        const canvas = OverlayCanvas.ComputeCanvasTransform(pose, tan_half_fov, target_height, pixels_per_unit);
        const scene_name = if (scene.GetComponent(SceneNameComponent)) |name_component| name_component.mName.items else "<unnamed>";

        try Text(frame_allocator, "Overlay '{s}' ({s}, {d:.2} px per unit)", .{ scene_name, @tagName(scene_component.mOverlayScaleMode), pixels_per_unit });
        if (canvas.RayToCanvasPoint(ray)) |point| {
            try Text(frame_allocator, "\tCanvas point: {d:.1}, {d:.1}", .{ point.x, point.y });
        } else {
            try Text(frame_allocator, "\tCanvas point: none", .{});
        }
    }
    if (overlay_count == 0) try Text(frame_allocator, "No overlay scenes in this world", .{});
}

pub fn OnTogglePanelEvent(self: *PickingDebugPanel) void {
    self._P_Open = !self._P_Open;
}

fn Text(frame_allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(frame_allocator, fmt, args);
    imgui.igTextUnformatted(text.ptr, text.ptr + text.len);
}
