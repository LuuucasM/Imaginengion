const std = @import("std");

const Input = @import("../Inputs/Input.zig");
const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const MouseScrolledEvent = @import("../Events/SystemEvent.zig").MouseScrolledEvent;

const math = std.math;
const LinAlg = @import("../Math/LinAlg.zig");
const Mat4f32 = LinAlg.Mat4f32;
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Quatf32 = LinAlg.Quatf32;
const EditorCamera = @This();

pub const ProjectionType = enum {
    Perspective,
    Orthographic,
};

mProjectionType: ProjectionType = .Perspective,

mOrthographicSize: f32 = 10.0,
mOrthographicNear: f32 = -1.0,
mOrthographicFar: f32 = 1.0,

mFOVDegrees: f32 = 45.0,
mNearClip: f32 = 0.1,
mFarClip: f32 = 1000.0,

mProjectionMatrix: Mat4f32 = LinAlg.Mat4Identity(),
mViewMatrix: Mat4f32 = LinAlg.Mat4Identity(),

mFocalPoint: Vec3f32 = std.mem.zeroes(Vec3f32),
mPosition: Vec3f32 = std.mem.zeroes(Vec3f32),
mCurrentMousePos: Vec2f32 = std.mem.zeroes(Vec2f32),

mDistance: f32 = 10.0,
mPitch: f32 = 0.0,
mYaw: f32 = 0.0,

mViewportWidth: usize = undefined,
mViewportHeight: usize = undefined,
mAspectRatio: f32 = undefined,
mIsFixedAspectRatio: bool = false,

pub fn Init(width: usize, height: usize) EditorCamera {
    var new_camera = EditorCamera{};
    new_camera.UpdateProjection();
    new_camera.UpdateView();
    new_camera.SetViewportSize(width, height);
    return new_camera;
}

pub fn InputUpdate(self: *EditorCamera) void {
    if (Input.IsKeyPressed(.LeftAlt)) {
        const new_pos = Input.GetMousePosition();
        const delta = new_pos - self.mCurrentMousePos * @as(Vec2f32, @splat(0.003));
        self.mCurrentMousePos = new_pos;

        if (Input.IsMouseButtonPressed(.ButtonMiddle)) {
            self.MousePan(delta);
        } else if (Input.IsMouseButtonPressed(.ButtonLeft)) {
            self.MouseRotate(delta);
        } else if (Input.IsMouseButtonPressed(.ButtonRight)) {
            self.MouseZoom(delta[1]);
        }
    }

    self.UpdateView();
}

pub fn OnInputEvent(self: *EditorCamera, event: SystemEvent) void {
    switch (event) {
        .ET_MouseScrolled => |e| self.OnMouseScroll(e),
        else => {},
    }
}

pub fn GetDistance(self: EditorCamera) f32 {
    return self.mDistance;
}

pub fn SetDistance(self: *EditorCamera, value: f32) void {
    self.mDistance = value;
}

pub fn GetProjection(self: EditorCamera) Mat4f32 {
    return self.mProjectionMatrix;
}

pub fn GetViewMatrix(self: EditorCamera) Mat4f32 {
    return self.mViewMatrix;
}

pub fn GetViewProjection(self: EditorCamera) Mat4f32 {
    return LinAlg.Mat4MulMat4(self.mProjectionMatrix, self.mViewMatrix);
}

pub fn SetViewportSize(self: *EditorCamera, width: usize, height: usize) void {
    self.mViewportWidth = width;
    self.mViewportHeight = height;
    self.UpdateProjection();
}

fn UpdateProjection(self: *EditorCamera) void {
    self.mAspectRatio = @as(f32, @floatFromInt(self.mViewportWidth)) / @as(f32, @floatFromInt(self.mViewportHeight));
    self.mProjectionMatrix = LinAlg.PerspectiveRHNO(LinAlg.DegreesToRadians(self.mFOVDegrees), self.mAspectRatio, self.mNearClip, self.mFarClip);
}

fn UpdateView(self: *EditorCamera) void {
    self.CalculatePosition();
    self.mViewMatrix = LinAlg.Mat4MulMat4(LinAlg.Mat4Inverse(LinAlg.Translate(self.mPosition)), LinAlg.QuatToMat4(self.GetOrientation()));
}

fn OnMouseScroll(self: *EditorCamera, e: MouseScrolledEvent) bool {
    const delta = e._YOffset * 0.1;
    self.MouseZoom(delta);
    self.UpdateView();
    return false;
}

fn MousePan(self: *EditorCamera, delta: Vec2f32) void {
    const speed = self.PanSpeed();
    self.mFocalPoint += -self.GetRightDirection() * @as(Vec3f32, @splat(delta[0])) * @as(Vec3f32, @splat(speed[0])) * @as(Vec3f32, @splat(self.mDistance));
    self.mFocalPoint += self.GetUpDirection() * @as(Vec3f32, @splat(delta[1])) * @as(Vec3f32, @splat(speed[1])) * @as(Vec3f32, @splat(self.mDistance));
}

fn MouseRotate(self: *EditorCamera, delta: Vec2f32) void {
    const yawSign: f32 = if (self.GetUpDirection()[1] < 0) -1.0 else 1.0;
    self.mYaw += yawSign * delta[0] * self.RotationSpeed();
    self.mPitch += delta[1] * self.RotationSpeed();
}

fn MouseZoom(self: *EditorCamera, delta: f32) void {
    self.mDistance -= delta * self.ZoomSpeed();
    if (self.mDistance < 1.0) {
        self.mFocalPoint += self.GetForwardDirection();
        self.mDistance = 1.0;
    }
}

fn CalculatePosition(self: *EditorCamera) void {
    self.mPosition = self.mFocalPoint - self.GetForwardDirection() * @as(Vec3f32, @splat(self.mDistance));
}

fn PanSpeed(self: EditorCamera) Vec2f32 {
    const x: f32 = if (@as(f32, @floatFromInt(self.mViewportWidth)) / 1000.0 < 2.4) @as(f32, @floatFromInt(self.mViewportWidth)) / 1000.0 else 2.4;
    const xFactor = 0.0336 * (x * x) - 0.1778 * x + 0.3021;
    const y: f32 = if (@as(f32, @floatFromInt(self.mViewportWidth)) / 1000.0 < 2.4) @as(f32, @floatFromInt(self.mViewportWidth)) / 1000.0 else 2.4;
    const yFactor = 0.0336 * y * y - 0.1778 * y + 0.3021;
    return .{ xFactor, yFactor };
}

fn RotationSpeed(self: EditorCamera) f32 {
    _ = self;
    return 0.8;
}

fn ZoomSpeed(self: EditorCamera) f32 {
    var dist = self.mDistance * 0.2;
    dist = std.math.clamp(dist, 0, std.math.floatMax(f32));

    var speed = dist * dist;
    speed = std.math.clamp(speed, 0.0, 100.0);

    return speed;
}

fn GetUpDirection(self: EditorCamera) Vec3f32 {
    return LinAlg.RotateVec3Quat(self.GetOrientation(), Vec3f32{ 0.0, 1.0, 0.0 });
}

fn GetRightDirection(self: EditorCamera) Vec3f32 {
    return LinAlg.RotateVec3Quat(self.GetOrientation(), Vec3f32{ 1.0, 0.0, 0.0 });
}

fn GetForwardDirection(self: EditorCamera) Vec3f32 {
    return LinAlg.RotateVec3Quat(self.GetOrientation(), Vec3f32{ 0.0, 0.0, -1.0 });
}

fn GetOrientation(self: EditorCamera) Quatf32 {
    return LinAlg.Vec3ToQuat(Vec3f32{ -self.mPitch, -self.mYaw, 0.0 });
}
