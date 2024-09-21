const std = @import("std");
const Input = @import("../Inputs/Input.zig");
const Event = @import("../Events/Event.zig").Event;
const MouseScrolledEvent = @import("../Events/InputEvents.zig").MouseScrolledEvent;
const math = std.math;
const LinAlg = @import("../Math/LinAlg.zig");
const Mat4f32 = LinAlg.Mat4f32;
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Quatf32 = LinAlg.Quatf32;
const EditorCamera = @This();

_FOV: f32 = 45.0,
_AspectRatio: f32 = 1.778,
_NearClip: f32 = 0.1,
_FarClip: f32 = 1000.0,

_ViewMatrix: Mat4f32 = std.mem.zeroes(Mat4f32),
_Position: Vec3f32 = std.mem.zeroes(Vec3f32),
_FocalPoint: Vec3f32 = std.mem.zeroes(Vec3f32),
_CurrentMousePos: Vec2f32 = std.mem.zeroes(Vec2f32),

_Distance: f32 = 10.0,
_Pitch: f32 = 0.0,
_Yaw: f32 = 0.0,

_ViewportWidth: f32 = 1600.0,
_ViewportHeight: f32 = 900.0,

_ProjectionMatrix: Mat4f32 = LinAlg.InitMat4CompTime(1.0),

_EngineAllocator: std.mem.Allocator,

pub fn Init(EngineAllocator: std.mem.Allocator) *EditorCamera {
    const ptr = try EngineAllocator.create(EditorCamera);
    ptr.* = .{};
    ptr.*.UpdateView();
    return ptr;
}
pub fn Deinit(self: *EditorCamera) void {
    self._EngineAllocator.destroy(self);
}

pub fn OnUpdate(self: *EditorCamera) void {
    if (Input.IsKeyPressed(.LeftAlt)) {
        const pos = Input.GetMousePosition();
        const delta = pos - self._CurrentMousePos * @as(Vec2f32, @splat(0.003));
        self._CurrentMousePos = pos;

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

pub fn OnInputEvent(self: *EditorCamera, event: Event) void {
    _ = switch (event) {
        .ET_MouseScrolled => |e| self.OnMouseScroll(e),
        else => false,
    };
}

pub fn GetDistance(self: EditorCamera) f32 {
    return self._Distance;
}

pub fn GetProjection(self: EditorCamera) *const Mat4f32 {
    return self._ProjectionMatrix;
}

pub fn GetViewMatrix(self: EditorCamera) *const Mat4f32 {
    return self._ViewMatrix;
}

pub fn GetViewProjection(self: EditorCamera) Mat4f32 {
    return LinAlg.Mat4Mul(self._ProjectionMatrix, self._ViewMatrix);
}

pub fn SetDistance(self: *EditorCamera, value: f32) void {
    self._Distance = value;
}

pub fn SetViewportSize(self: *EditorCamera, width: f32, height: f32) void {
    self._ViewportWidth = width;
    self._ViewportHeight = height;
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

fn GetPosition(self: EditorCamera) Vec3f32 {
    return self._Position;
}

fn GetOrientation(self: EditorCamera) Quatf32 {
    return LinAlg.Vec3ToQuat(Vec3f32{ -self._Pitch, -self._Yaw, 0.0 });
}

fn GetPitch(self: EditorCamera) f32 {
    return self._Pitch;
}

fn GetYaw(self: EditorCamera) f32 {
    return self._Yaw;
}

fn UpdateProjection(self: *EditorCamera) void {
    self._AspectRatio = self._ViewportWidth / self._ViewportHeight;
    self._ProjectionMatrix = LinAlg.PerspectiveRHNO(LinAlg.Radians(self._FOV), self._AspectRatio, self._NearClip, self._FarClip);
}

fn UpdateView(self: *EditorCamera) void {
    self.CalculatePosition();
    self._ViewMatrix = LinAlg.Translate(LinAlg.InitMat4CompTime(1.0), self._Position) * LinAlg.QuatToMat4(self.GetOrientation());
    self._ViewMatrix = LinAlg.Mat4Inverse(self._ViewMatrix);
}

fn OnMouseScroll(self: *EditorCamera, e: MouseScrolledEvent) bool {
    const delta = e._YOffset * 0.1;
    self.MouseZoom(delta);
    self.UpdateView();
    return false;
}

fn MousePan(self: *EditorCamera, delta: Vec2f32) void {
    const speed = self.PanSpeed();
    self._FocalPoint += -self.GetRightDirection() * @as(Vec3f32, @splat(delta[0])) * @as(Vec3f32, @splat(speed[0])) * @as(Vec3f32, @splat(self._Distance));
    self._FocalPoint += self.GetUpDirection() * @as(Vec3f32, @splat(delta[1])) * @as(Vec3f32, @splat(speed[1])) * @as(Vec3f32, @splat(self._Distance));
}

fn MouseRotate(self: *EditorCamera, delta: Vec2f32) void {
    const yawSign: f32 = if (self.GetUpDirection()[1] < 0) -1.0 else 1.0;
    self._Yaw += yawSign * delta[0] * self.RotationSpeed();
    self._Pitch += delta[1] * self.RotationSpeed();
}

fn MouseZoom(self: *EditorCamera, delta: f32) void {
    self._Distance -= delta * self.ZoomSpeed();
    if (self._Distance < 1.0) {
        self._FocalPoint += self.GetForwardDirection();
        self._Distance = 1.0;
    }
}

fn CalculatePosition(self: EditorCamera) Vec3f32 {
    return self._FocalPoint - self.GetForwardDirection() * @as(Vec3f32, @splat(self._Distance));
}

fn PanSpeed(self: EditorCamera) Vec2f32 {
    const x: f32 = if (self._ViewportWidth / 1000.0 < 2.4) self._ViewportWidth / 1000.0 else 2.4;
    const xFactor = 0.0336 * x * x - 0.1778 * x + 0.3021;
    const y: f32 = if (self._ViewportHeight / 1000.0 < 2.4) self._ViewportHeight / 1000.0 else 2.4;
    const yFactor = 0.0336 * y * y - 0.1778 * y + 0.3021;
    return .{ xFactor, yFactor };
}

fn RotationSpeed(self: EditorCamera) f32 {
    _ = self;
    return 0.8;
}

fn ZoomSpeed(self: EditorCamera) f32 {
    var dist = self._Distance * 0.2;
    dist = if (dist > 0.0) dist else 0.0;
    var speed = dist * dist;
    speed = if (speed < 100.0) speed else 100.0;

    return speed;
}
