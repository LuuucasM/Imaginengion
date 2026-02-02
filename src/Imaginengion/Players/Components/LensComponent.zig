const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;
const FrameBuffer = @import("../../FrameBuffers/FrameBuffer.zig");
const VertexArray = @import("../../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../../IndexBuffers/IndexBuffer.zig");
const Entity = @import("../Entity.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const LinAlg = @import("../../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;
const Mat4f32 = LinAlg.Mat4f32;

const LensComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;

pub const Name: []const u8 = "LensComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == LensComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

//viewport stuff
mViewportWidth: usize = 1600,
mViewportHeight: usize = 900,
mAspectRatio: f32 = 0.0,

mFrameBuffer: FrameBuffer = undefined,
mVertexArray: VertexArray = undefined,
mVertexBuffer: VertexBuffer = undefined,
mIndexBuffer: IndexBuffer = undefined,

mProjection: Mat4f32 = LinAlg.Mat4Identity(),

mIsFixedAspectRatio: bool = false,
mPerspectiveFOVRad: f32 = LinAlg.DegreesToRadians(60.0),
mPerspectiveNear: f32 = 0.01,
mPerspectiveFar: f32 = 1000.0,
mAreaRect: Vec4f32 = Vec4f32{ 0.0, 0.0, 1.0, 1.0 },

//offsets
OffsetPosition: Vec3f32 = .{ 0.0, 0.0, 0.0 },
OffsetRotation: Quatf32 = .{ 1.0, 0.0, 0.0, 0.0 },

pub fn Deinit(self: *LensComponent, engine_context: *EngineContext) !void {
    self.mFrameBuffer.Deinit(engine_context.EngineAllocator());
    self.mVertexArray.Deinit(engine_context.EngineAllocator());
    self.mVertexBuffer.Deinit(engine_context.EngineAllocator());
    self.mIndexBuffer.Deinit();
}

pub fn SetPerspective(self: *LensComponent, fov_radians: f32, near_clip: f32, far_clip: f32) void {
    self.mPerspectiveFOVRad = fov_radians;
    self.mPerspectiveNear = near_clip;
    self.mPerspectiveFar = far_clip;
    self.RecalculateProjection();
}

pub fn SetAreaRect(self: *LensComponent, new_area: Vec4f32) void {
    self.mAreaRect = new_area;
    self.mFrameBuffer.Resize(@intFromFloat(@as(f32, @floatFromInt(self.mViewportWidth)) * self.mAreaRect[2]), @intFromFloat(@as(f32, @floatFromInt(self.mViewportHeight)) * self.mAreaRect[3]));
}

pub fn SetViewportSize(self: *LensComponent, width: usize, height: usize) void {
    self.mViewportWidth = width;
    self.mViewportHeight = height;

    self.mFrameBuffer.Resize(@intFromFloat(@as(f32, @floatFromInt(self.mViewportWidth)) * self.mAreaRect[2]), @intFromFloat(@as(f32, @floatFromInt(self.mViewportHeight)) * self.mAreaRect[3]));

    if (height > 0) {
        self.mAspectRatio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
    } else {
        self.mAspectRatio = 0.0;
    }
    self.RecalculateProjection();
}

fn RecalculateProjection(self: *LensComponent) void {
    self.mProjection = LinAlg.PerspectiveRHNO(self.mPerspectiveFOVRad, self.mAspectRatio, self.mPerspectiveNear, self.mPerspectiveFar);
}

pub fn EditorRender(self: *LensComponent, _: *EngineContext) !void {

    //aspect ratio
    _ = imgui.igCheckbox("Set fixed aspect ratio", &self.mIsFixedAspectRatio);

    //print the size/far/near variables depending on projection type
    var perspective_degrees = LinAlg.RadiansToDegrees(self.mPerspectiveFOVRad);
    if (imgui.igDragFloat("FOV", &perspective_degrees, 1.0, 0.0, 0.0, "%.3f", imgui.ImGuiSliderFlags_None) == true) {
        self.mPerspectiveFOVRad = LinAlg.DegreesToRadians(perspective_degrees);
        self.RecalculateProjection();
    }

    if (imgui.igDragFloat("Near", &self.mPerspectiveNear, 1.0, 0.0, 0.0, "%.3f", imgui.ImGuiSliderFlags_None) == true) {
        self.RecalculateProjection();
    }

    if (imgui.igDragFloat("Far", &self.mPerspectiveFar, 1.0, 0.0, 0.0, "%.3f", imgui.ImGuiSliderFlags_None) == true) {
        self.RecalculateProjection();
    }

    var rect_area: [4]f32 = [4]f32{ self.mAreaRect[0], self.mAreaRect[1], self.mAreaRect[2], self.mAreaRect[3] };

    if (imgui.igDragFloat4("Area Rect", &rect_area[0], 0.01, 0.0, 1.0, "%.3f", imgui.ImGuiSliderFlags_None)) {
        self.SetAreaRect(Vec4f32{ rect_area[0], rect_area[1], rect_area[2], rect_area[3] });
    }
}

pub fn jsonStringify(self: *const LensComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("IsFixedAspectRatio");
    try jw.write(self.mIsFixedAspectRatio);

    try jw.objectField("PerspectiveFOVRad");
    try jw.write(self.mPerspectiveFOVRad);

    try jw.objectField("PerspectiveNear");
    try jw.write(self.mPerspectiveNear);

    try jw.objectField("PerspectiveFar");
    try jw.write(self.mPerspectiveFar);

    try jw.objectField("AreaRect");
    try jw.write(self.mAreaRect);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!LensComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    var result: LensComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "IsFixedAspectRatio")) {
            result.mIsFixedAspectRatio = try std.json.innerParse(bool, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "PerspectiveFOVRad")) {
            result.mPerspectiveFOVRad = try std.json.innerParse(f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "PerspectiveNear")) {
            result.mPerspectiveNear = try std.json.innerParse(f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "PerspectiveFar")) {
            result.mPerspectiveFar = try std.json.innerParse(f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "AreaRect")) {
            result.mAreaRect = try std.json.innerParse(Vec4f32, frame_allocator, reader, options);
        }
    }
    result.RecalculateProjection();

    return result;
}
