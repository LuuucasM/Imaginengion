const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;

const Entity = @import("../ECSObjects/Entity.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntityTransformComponent = EntityComponents.TransformComponent;
const SceneLayer = @import("../ECSObjects/Scene.zig");

const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
const Mat4 = MathTypes.Mat4;
const Vec4 = MathTypes.Vec4;
const ScreenRect = @import("../Math/ScreenRect.zig");

const Player = @import("../ECSObjects/Player.zig");

const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");

const WindowEventData = @import("../Events/WindowEventData.zig");
const KeyboardPressedEvent = WindowEventData.KeyboardPressedEvent;

const ComputeOutput = @import("../Renderer/Renderer.zig").ComputeOutput;

const ViewportPanel = @This();

pub const Panel = enum {
    Viewport,
    Play,
};

/// A render target for a panel to show, and the player whose viewpoint rendered it.
pub const PanelImage = struct {
    FrameBuffer: *ComputeOutput,
    AreaRect: Vec4(f32),
    Camera: Player,
};

/// A render target image as it was drawn on screen. Kept until the panel draws again, so the next
/// frame's input can map the mouse onto what was actually on screen when it clicked. Holds handles,
/// never component pointers: components can be added in between, which can move the ECS arrays.
/// Player.GetRenderView resolves the transform and viewpoint when they are needed.
pub const ViewRect = struct {
    Rect: ScreenRect.ScreenRect,
    Camera: Player, //whose viewpoint rendered the image
    World: EngineContext.WorldType, //whose entities are in it, not necessarily the camera's own world
};

pub const ViewAt = struct {
    Panel: Panel,
    View: ViewRect,
    Pixel: Vec2(f32), //continuous render target pixel, ready for CameraRay.MakeRay
};

//for viewport window
mP_OpenViewport: bool = true,
mIsFocusedViewport: bool = false,
mIsHoveredViewport: bool = false,
mViewportWidth: usize = 0,
mViewportHeight: usize = 0,
mViewportRects: std.ArrayList(ViewRect) = .empty,

//for play window
mP_OpenPlay: bool = true,
mIsFocusedPlay: bool = false,
mIsHoveredPlay: bool = false,
mPlayWidth: usize = 0,
mPlayHeight: usize = 0,
mPlayRects: std.ArrayList(ViewRect) = .empty,

pub fn Init(self: *ViewportPanel, viewport_width: usize, viewport_height: usize) void {
    self.mViewportWidth = viewport_width;
    self.mViewportHeight = viewport_height;

    self.mPlayWidth = viewport_width;
    self.mPlayHeight = viewport_height;
}

pub fn Deinit(self: *ViewportPanel, engine_allocator: std.mem.Allocator) void {
    self.mViewportRects.deinit(engine_allocator);
    self.mPlayRects.deinit(engine_allocator);
}

/// The view under `screen_pos` (window coordinates, like InputManager's mouse position), as of the
/// last time the panels were drawn. Only a hovered panel counts, so a popup, menu or window over
/// the viewport blocks it. Overlapping area rects resolve to the one drawn last, which is on top.
pub fn FindViewAt(self: *const ViewportPanel, screen_pos: Vec2(f32)) ?ViewAt {
    if (self.mIsHoveredViewport) {
        if (FindInRects(self.mViewportRects.items, screen_pos)) |found| return .{ .Panel = .Viewport, .View = found.View, .Pixel = found.Pixel };
    }
    if (self.mIsHoveredPlay) {
        if (FindInRects(self.mPlayRects.items, screen_pos)) |found| return .{ .Panel = .Play, .View = found.View, .Pixel = found.Pixel };
    }
    return null;
}

fn FindInRects(rects: []const ViewRect, screen_pos: Vec2(f32)) ?struct { View: ViewRect, Pixel: Vec2(f32) } {
    var i = rects.len;
    while (i > 0) {
        i -= 1;
        if (ScreenRect.ToTargetPixel(rects[i].Rect, screen_pos)) |pixel| return .{ .View = rects[i], .Pixel = pixel };
    }
    return null;
}

pub fn OnImguiRenderViewport(self: *ViewportPanel, engine_context: *EngineContext, images: []const PanelImage, world: EngineContext.WorldType) !void {
    const zone = Tracy.ZoneInit("ViewportPanel::OnImguiRenderViewport", @src());
    defer zone.Deinit();

    //a closed panel shows nothing, so it must not keep reporting what it showed before
    self.mViewportRects.clearRetainingCapacity();
    self.mIsHoveredViewport = false;

    if (self.mP_OpenViewport == false) return;

    _ = imgui.igBegin("Viewport", null, 0);
    defer imgui.igEnd();

    //update viewport size if needed
    var viewport_size = imgui.igGetContentRegionAvail();

    if (viewport_size.x != @as(f32, @floatFromInt(self.mViewportWidth)) or viewport_size.y != @as(f32, @floatFromInt(self.mViewportHeight))) {
        if (viewport_size.x < 0) viewport_size.x = 0;
        if (viewport_size.y < 0) viewport_size.y = 0;
        self.mViewportWidth = @intFromFloat(viewport_size.x);
        self.mViewportHeight = @intFromFloat(viewport_size.y);
    }

    //get if the window is focused or not
    self.mIsFocusedViewport = imgui.igIsWindowFocused(imgui.ImGuiFocusedFlags_None);
    //false while a popup, menu or another window is over it, which is what picking wants
    self.mIsHoveredViewport = imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None);
    try OnImguiRender(engine_context, images, world, viewport_size, &self.mViewportRects);
}

pub fn OnImguiRenderPlay(self: *ViewportPanel, engine_context: *EngineContext, images: []const PanelImage, world: EngineContext.WorldType) !void {
    const zone = Tracy.ZoneInit("ViewportPanel::OnImguiRenderPlay", @src());
    defer zone.Deinit();

    self.mPlayRects.clearRetainingCapacity();
    self.mIsHoveredPlay = false;

    if (self.mP_OpenPlay == false) return;

    _ = imgui.igBegin("PlayPanel", null, 0);
    defer imgui.igEnd();

    //update viewport size if needed
    var viewport_size = imgui.igGetContentRegionAvail();
    if (viewport_size.x != @as(f32, @floatFromInt(self.mPlayWidth)) or viewport_size.y != @as(f32, @floatFromInt(self.mPlayHeight))) {
        if (viewport_size.x < 0) viewport_size.x = 0;
        if (viewport_size.y < 0) viewport_size.y = 0;
        self.mPlayWidth = @intFromFloat(viewport_size.x);
        self.mPlayHeight = @intFromFloat(viewport_size.y);
    }

    //get if the window is focused or not
    self.mIsFocusedPlay = imgui.igIsWindowFocused(imgui.ImGuiFocusedFlags_None);
    self.mIsHoveredPlay = imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None);

    try OnImguiRender(engine_context, images, world, viewport_size, &self.mPlayRects);
}

fn OnImguiRender(engine_context: *EngineContext, images: []const PanelImage, world: EngineContext.WorldType, viewport_size: imgui.ImVec2, view_rects: *std.ArrayList(ViewRect)) !void {
    const zone = Tracy.ZoneInit("ViewportPanel::OnImguiRender", @src());
    defer zone.Deinit();

    //with multi-viewports off this is relative to the app window, the same space as the mouse.
    //turning ImGuiConfigFlags_ViewportsEnable on would make it desktop coordinates instead.
    const viewport_pos = imgui.igGetCursorScreenPos();

    for (images) |image| {
        const rect = image.AreaRect;
        const frame_buffer = image.FrameBuffer;

        const x = viewport_pos.x + rect.x * viewport_size.x;
        const y = viewport_pos.y + rect.y * viewport_size.y;
        const w = rect.z * viewport_size.x;
        const h = rect.w * viewport_size.y;

        const tex_ref = imgui.ImTextureRef_c{
            ._TexData = null,
            ._TexID = @as(imgui.ImTextureID, @intFromPtr(frame_buffer.GetTexture())),
        };

        const draw_list = imgui.igGetWindowDrawList();
        imgui.ImDrawList_AddImage(
            draw_list,
            tex_ref,
            .{ .x = x, .y = y },
            .{ .x = x + w, .y = y + h },
            .{ .x = 0, .y = 0 },
            .{ .x = 1, .y = 1 },
            0xFFFFFFFF,
        );

        //the list outlives the frame (it is read during next frame's input), so it can't use the frame allocator
        try view_rects.append(engine_context.EngineAllocator(), .{
            .Rect = .{
                .Min = .{ .x = x, .y = y },
                .Size = .{ .x = w, .y = h },
                .TargetSize = .{ .x = @floatFromInt(frame_buffer.GetWidth()), .y = @floatFromInt(frame_buffer.GetHeight()) },
            },
            .Camera = image.Camera,
            .World = world,
        });
    }
}

pub fn OnTogglePanelEventViewport(self: *ViewportPanel) void {
    self.mP_OpenViewport = !self.mP_OpenViewport;
}

pub fn OnTogglePanelEventPlay(self: *ViewportPanel) void {
    self.mP_OpenPlay = !self.mP_OpenPlay;
}

pub fn OnSelectEntityEvent(self: *ViewportPanel, new_entity: ?Entity) void {
    self.mSelectedEntity = new_entity;
}

pub fn OnInputPressedEvent(self: *ViewportPanel, e: KeyboardPressedEvent) bool {
    _ = self;
    _ = e;
    //switch (e._InputCode) {
    //    .Q => {
    //        self.mGizmoType = .None;
    //    },
    //    .W => {
    //        self.mGizmoType = .Translate;
    //    },
    //    .E => {
    //        self.mGizmoType = .Rotation;
    //    },
    //    .R => {
    //        self.mGizmoType = .Scale;
    //    },
    //    else => return true,
    //}
    return true;
}

pub fn OnDeleteEntity(self: *ViewportPanel, delete_entity: Entity) void {
    if (self.mSelectedEntity) |selected_entity| {
        if (selected_entity.mID == delete_entity.mID) {
            self.mSelectedEntity = null;
        }
    }
}
