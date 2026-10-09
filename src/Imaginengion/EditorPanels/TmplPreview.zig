//! A template's preview, in the editor's own UI: the scene the template is in drawn from a fixed camera, shown on a quad
//! that fills its pane. The camera is a player of its own in the editor world possessing a camera entity, set up like
//! the editor's viewport camera (EditorProgram), so the quad shows it the way the viewport does: its view sized to the
//! quad (Viewports.FitPlayerToQuad) and copied onto it each frame. Clicking it picks nothing: it isn't a view into the
//! world being edited (EditorProgram.ViewUnder)
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const RenderStats = @import("../Core/EngineStats.zig").RenderStats;
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const Viewports = @import("../Renderer/Viewports.zig");
const Widgets = @import("../UI/Widgets.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const ViewpointComponent = EntityComponents.ViewpointComponent;
const RenderTargetComponent = @import("../ECSComponents/PComponents.zig").RenderTargetComponent;
const Vec3 = @import("../Math/MathTypes.zig").Vec3;

const TmplPreview = @This();

/// Where the camera sits: the same spot as the editor's own camera, looking at the origin where every template's root
/// is (Make Template resets it there)
pub const CAMERA_POSITION: Vec3(f32) = .{ .x = 0.0, .y = 0.0, .z = 15.0 };

/// The camera player, whose render target the quad shows
mPlayer: Player,
/// The entity it possesses, in the editor world's camera scene
mCamera: Entity,
mQuad: Entity,
/// What the preview drew, kept apart from the worlds' own stats
mStats: RenderStats = .{},

/// The camera, in `camera_scene` (a game layer scene in the editor world), and its quad, filling `pane`
pub fn Build(engine_context: *EngineContext, camera_scene: Scene, pane: Entity) !TmplPreview {
    const zone = Tracy.ZoneInit("TmplPreview::Build", @src());
    defer zone.Deinit();
    const player = try engine_context.mEditorWorld.CreatePlayer(engine_context, .{
        .bAddNameComponent = true,
        .bAddUUIDComponent = false,
        .bAddRenderComponent = false,
        .bAddPossessComponent = true,
        .bAddMicComponent = false,
    });
    //with no texture yet: the first fit to its quad (Render) makes one the quad's size
    _ = try player.AddComponent(engine_context, RenderTargetComponent{});
    try player.SetName(engine_context, "Template Preview");
    const camera = try camera_scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try camera.SetName(engine_context, "Template Preview Camera");
    try camera.SetTranslation(engine_context, CAMERA_POSITION);
    _ = try camera.AddComponent(engine_context, PlayerSlotComponent{});
    _ = try camera.AddComponent(engine_context, ViewpointComponent{});
    player.Possess(camera);
    return .{
        .mPlayer = player,
        .mCamera = camera,
        .mQuad = try Widgets.Viewport(engine_context, .{ .Entity = pane }, player),
    };
}

/// Draws `scene` into the camera's view, sized to the quad as `ui_view` (the editor UI's camera) sees it. Inside the
/// renderer's frame and before the editor UI is drawn, which is what copies the view onto the quad
pub fn Render(self: *TmplPreview, engine_context: *EngineContext, scene: Scene, ui_view: Renderer.CameraView) !void {
    const zone = Tracy.ZoneInit("TmplPreview::Render", @src());
    defer zone.Deinit();
    try Viewports.FitPlayerToQuad(engine_context, self.mQuad, ui_view);
    const render_view = self.mPlayer.GetRenderView() orelse return;
    //a quad with no size yet has nothing made to draw into
    if (!render_view.mRenderTarget.mComputeTexture.IsCreated()) return;
    //the renderer adds to stats, and these are only ever this frame's preview
    self.mStats.ResetStats();
    try engine_context.mRenderer.RenderScene(
        scene,
        &self.mStats,
        engine_context,
        Renderer.BuildPushConstants(render_view.mTransform, render_view.mViewpoint),
        Renderer.CameraView.FromViewpoint(render_view.mTransform, render_view.mViewpoint, engine_context.mAppWindow.GetDisplayScale()),
        &render_view.mRenderTarget.mComputeTexture,
        .OverlayGame,
    );
}

/// The camera, its player and the quad, at the end of the frame
pub fn Delete(self: TmplPreview, engine_context: *EngineContext) !void {
    try self.mQuad.Delete(engine_context);
    try self.mCamera.Delete(engine_context);
    try self.mPlayer.Delete(engine_context);
}
