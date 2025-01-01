const std = @import("std");

// External modules (assumes these files exist in your project).
const Input            = @import("../Inputs/Input.zig");
const Event            = @import("../Events/Event.zig").Event;
const MouseScrolledEvt = @import("../Events/InputEvents.zig").MouseScrolledEvent;
const math             = std.math;
const LinAlg           = @import("../Math/LinAlg.zig");

/* Short aliases for readability. */
const Mat4f32 = LinAlg.Mat4f32;
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;

/**
 * @struct EditorCamera
 * @brief An orbital camera that can pan, rotate, and zoom, typically for editor tools.
 *
 * Fields starting with underscore are internal state; public methods
 * orchestrate changes and keep these fields in sync.
 */
pub const EditorCamera = struct {
    // Public (semi) constants for default behavior
    pub const DEFAULT_FOV       = 45.0;
    pub const DEFAULT_ASPECT    = 1.778;
    pub const DEFAULT_NEAR_CLIP = 0.1;
    pub const DEFAULT_FAR_CLIP  = 1000.0;

    // Internal fields
    _fov: f32        = DEFAULT_FOV,
    _aspectRatio: f32= DEFAULT_ASPECT,
    _nearClip: f32   = DEFAULT_NEAR_CLIP,
    _farClip: f32    = DEFAULT_FAR_CLIP,

    _projectionMatrix: Mat4f32 = LinAlg.InitMat4CompTime(1.0),
    _viewMatrix: Mat4f32       = std.mem.zeroes(Mat4f32),

    _focalPoint: Vec3f32   = .{ 0.0, 0.0, 0.0 },
    _position: Vec3f32     = .{ 0.0, 0.0, 0.0 },
    _currentMousePos: Vec2f32 = .{ 0.0, 0.0 },

    _distance: f32         = 10.0,
    _pitch: f32            = 0.0,
    _yaw: f32              = 0.0,

    _viewportWidth: f32  = 1600.0,
    _viewportHeight: f32 = 900.0,

    _engineAllocator: *std.mem.Allocator,

    /// Create a new EditorCamera object and initialize view/projection.
    pub fn init(allocator: *std.mem.Allocator) !*EditorCamera {
        const camPtr = try allocator.create(EditorCamera);
        // Use "dot init" to zero many fields if desired
        camPtr.* = .{ ._engineAllocator = allocator };
        camPtr.updateView();
        camPtr.updateProjection();
        return camPtr;
    }

    /// Destroy an EditorCamera object, freeing its memory.
    pub fn deinit(self: *EditorCamera) void {
        self._engineAllocator.destroy(self);
    }

    /// Called each frame, polls input and updates camera state accordingly.
    pub fn onUpdate(self: *EditorCamera) void {
        if (Input.isKeyPressed(.LeftAlt)) {
            const newPos = Input.getMousePosition();
            const delta: Vec2f32 = (newPos - self._currentMousePos) * 0.003;
            self._currentMousePos = newPos;

            if (Input.isMouseButtonPressed(.ButtonMiddle)) {
                self.mousePan(delta);
            } else if (Input.isMouseButtonPressed(.ButtonLeft)) {
                self.mouseRotate(delta);
            } else if (Input.isMouseButtonPressed(.ButtonRight)) {
                // For zoom, we only use delta.y
                self.mouseZoom(delta.y);
            }
        }
        self.updateView();
    }

    /// Called when a new input event occurs, e.g. mouse scroll.
    pub fn onInputEvent(self: *EditorCamera, event: Event) void {
        switch (event) {
            .ET_MouseScrolled => |msEvt| {
                self.onMouseScroll(msEvt);
            },
            else => {},
        }
    }

    /// Accessors
    pub fn getDistance(self: EditorCamera) f32 {
        return self._distance;
    }

    pub fn setDistance(self: *EditorCamera, dist: f32) void {
        self._distance = dist;
    }

    pub fn getProjection(self: EditorCamera) *const Mat4f32 {
        return &self._projectionMatrix;
    }

    pub fn getViewMatrix(self: EditorCamera) *const Mat4f32 {
        return &self._viewMatrix;
    }

    /// Returns the product of projection * view, for rendering.
    pub fn getViewProjection(self: EditorCamera) Mat4f32 {
        return LinAlg.Mat4Mul(self._projectionMatrix, self._viewMatrix);
    }

    /// Set the viewport dimension so we can recalc aspect ratio, projection, etc.
    pub fn setViewportSize(self: *EditorCamera, width: f32, height: f32) void {
        self._viewportWidth = width;
        self._viewportHeight = height;
        self.updateProjection();
    }

    /// Recompute projection matrix for changes to FOV, aspect, near/far, etc.
    fn updateProjection(self: *EditorCamera) void {
        self._aspectRatio = self._viewportWidth / self._viewportHeight;
        self._projectionMatrix = LinAlg.perspectiveRHNO(
            LinAlg.radians(self._fov),
            self._aspectRatio,
            self._nearClip,
            self._farClip,
        );
    }

    /// Recompute view matrix for changes to position, yaw, pitch, etc.
    fn updateView(self: *EditorCamera) void {
        // Calculate camera position from focal point & orientation
        self.calculatePosition();
        const orientation = self.getOrientation();

        // camera transform = translate * rotation, then invert for view matrix
        var transform = LinAlg.translate(LinAlg.InitMat4CompTime(1.0), self._position);
        transform = transform * LinAlg.QuatToMat4(orientation);

        self._viewMatrix = LinAlg.Mat4Inverse(transform);
    }

    /// Process a mouse-scrolled event for zoom in/out.
    fn onMouseScroll(self: *EditorCamera, msEvt: MouseScrolledEvent) void {
        const zoomDelta = msEvt._yOffset * 0.1;
        self.mouseZoom(zoomDelta);
        self.updateView();
    }

    /// Move the camera's focal point horizontally and vertically, orbit style.
    fn mousePan(self: *EditorCamera, delta: Vec2f32) void {
        const speed = self.panSpeed();
        // Move in negative X direction
        self._focalPoint +=
            (self.getRightDir() * -delta.x * speed.x * self._distance)
            ++
            // Move in +Y direction
            (self.getUpDir() * delta.y * speed.y * self._distance);
    }

    /// Rotate the camera around the focal point, modifying yaw and pitch.
    fn mouseRotate(self: *EditorCamera, delta: Vec2f32) void {
        // if up is negative, invert yaw direction
        const yawSign: f32 = if (self.getUpDir().y < 0) -1.0 else 1.0;
        self._yaw   += yawSign * delta.x * self.rotationSpeed();
        self._pitch += delta.y * self.rotationSpeed();
    }

    /// Zoom the camera in/out by adjusting distance from focal point.
    fn mouseZoom(self: *EditorCamera, deltaY: f32) void {
        self._distance -= deltaY * self.zoomSpeed();

        // if distance goes below 1, clamp and shift focal point forward
        if (self._distance < 1.0) {
            self._focalPoint += self.getForwardDir();
            self._distance = 1.0;
        }
    }

    /// Update the internal _position based on the current focal point & orientation.
    fn calculatePosition(self: *EditorCamera) void {
        // pos = focal - forward * distance
        self._position = self._focalPoint - (self.getForwardDir() * self._distance);
    }

    /// Speed at which we pan camera with middle-drag.
    fn panSpeed(self: *EditorCamera) Vec2f32 {
        const xscale = math.min(self._viewportWidth / 1000.0, 2.4);
        const xFactor = 0.0336 * (xscale * xscale) - 0.1778 * xscale + 0.3021;

        const yscale = math.min(self._viewportHeight / 1000.0, 2.4);
        const yFactor = 0.0336 * (yscale * yscale) - 0.1778 * yscale + 0.3021;

        return .{ xFactor, yFactor };
    }

    /// Speed of camera rotation for left-drag.
    fn rotationSpeed(self: *EditorCamera) f32 {
        return 0.8; // constant
    }

    /// Speed of camera zoom for right-drag or mouse wheel.
    fn zoomSpeed(self: *EditorCamera) f32 {
        // max(0.0, distance*0.2), squared but clamped <= 100
        var dist = self._distance * 0.2;
        if (dist < 0) dist = 0.0;

        var speed = dist * dist;
        if (speed > 100.0) speed = 100.0;

        return speed;
    }

    /// Get various directions in world space, based on camera orientation.
    fn getUpDir(self: *EditorCamera) Vec3f32 {
        return LinAlg.rotateVec3Quat(self.getOrientation(), .{ 0.0, 1.0, 0.0 });
    }

    fn getRightDir(self: *EditorCamera) Vec3f32 {
        return LinAlg.rotateVec3Quat(self.getOrientation(), .{ 1.0, 0.0, 0.0 });
    }

    fn getForwardDir(self: *EditorCamera) Vec3f32 {
        return LinAlg.rotateVec3Quat(self.getOrientation(), .{ 0.0, 0.0, -1.0 });
    }

    /// Build orientation quaternion from yaw & pitch angles.
    fn getOrientation(self: *EditorCamera) Quatf32 {
        // Convert angles => quaternion. 
        // By convention, we do: pitch around x, yaw around y, 
        // negative signs for a typical "orbit" style camera usage.
        const rotVec = Vec3f32{ -self._pitch, -self._yaw, 0.0 };
        return LinAlg.vec3ToQuat(rotVec);
    }
};
