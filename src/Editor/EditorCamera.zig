const std = @import("std");
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
_InitialMousePos: Vec2f32 = std.mem.zeroes(Vec2f32),

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

pub fn OnUpdate(self: *EditorCamera) void {}

pub fn OnInputEvent(self: *EditorCamera) void {}

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

fn GetUpDirection(self: EditorCamera) Vec2f32 {}

fn GetRightDirection(self: EditorCamera) Vec3f32 {}

fn GetForwardDirection(self: EditorCamera) Vec3f32 {}

fn GetPosition(self: EditorCamera) Vec3f32 {
    return self._Position;
}

fn GetOrientation(self: EditorCamera) Quatf32 {}

fn GetPitch(self: EditorCamera) f32 {
    return self._Pitch;
}

fn GetYaw(self: EditorCamera) f32 {
    return self._Yaw;
}

fn UpdateProjection(self: *EditorCamera) void {
    self._AspectRatio = self._ViewportWidth / self._ViewportHeight;
    self._ProjectionMatrix = LinAlg.PerspectiveRHGL(LinAlg.Radians(self._FOV), self._AspectRatio, self._NearClip, self._FarClip);
}

fn UpdateView(self: *EditorCamera) void {
    self.CalculatePosition();
    self._ViewMatrix = LinAlg.Translate(LinAlg.InitMat4CompTime(1.0), self._Position) * LinAlg.QuatToMat4(self.GetOrientation()); //TODO: implement Translate, implement GetOrientation
    self._ViewMatrix = LinAlg.Mat4Inverse(self._ViewMatrix); //TODO: implement Mat4Inverse
}

fn OnMouseScroll(self: *EditorCamera) bool {}

fn MousePan(self: *EditorCamera, delta: Vec2f32) void {}

fn MouseRotate(self: *EditorCamera, delta: Vec2f32) void {}

fn MouseZoom(self: *EditorCamera, delta: Vec2f32) void {}

fn CalculatePosition(self: EditorCamera) Vec3f32 {
    return self._FocalPoint - self.GetForwardDirection() * @as(Vec3f32, @splat(self._Distance));
}

fn PanSpeed(self: EditorCamera) Vec2f32 {}

fn RotationSpeed(self: EditorCamera) f32 {}

fn ZoomSpeed(self: EditorCamera) f32 {}
