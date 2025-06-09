const std = @import("std");
const SSBO = @import("../SSBOs/SSBO.zig");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const ShaderAsset = @import("../Assets/Assets.zig").ShaderAsset;
const AssetHandle = @import("../Assets/AssetHandle.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const Renderer2D = @This();

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Quatf32 = LinAlg.Quatf32;
const Mat4f32 = LinAlg.Mat4f32;
const MAX_PATH_LEN = 256;

pub const QuadVertexPositions = Mat4f32{
    Vec4f32{ -0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, 0.5, 0.0, 1.0 },
    Vec4f32{ -0.5, 0.5, 0.0, 1.0 },
};

pub const QuadData = extern struct {
    Vertex1: [3]f32,
    Vertex2: [3]f32,
    Vertex3: [3]f32,
    Vertex4: [3]f32,
    Color: [4]f32,
    TexCoord1: [2]f32,
    TexCoord2: [2]f32,
    TexCoord3: [2]f32,
    TexCoord4: [2]f32,
    TexIndex: f32,
    TilingFactor: f32,
};

pub const CircleData = extern struct {
    Position: [3]f32,
    Normal: [3]f32,
    Radius: f32,
    Color: [4]f32,
};

pub const LineData = extern struct {
    P1: [3]f32,
    P2: [3]f32,
    Normal: [3]f32,
    Thickness: f32,
    Color: [4]f32,
};

const RectVertexPositions = Mat4f32{
    Vec4f32{ -0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, 0.5, 0.0, 1.0 },
    Vec4f32{ -0.5, 0.5, 0.0, 1.0 },
};

mAllocator: std.mem.Allocator,

mQuadBuffer: SSBO,
mQuadBufferBase: std.ArrayList(QuadData),

mCircleBuffer: SSBO,
mCircleBufferBase: std.ArrayList(CircleData),

mLineBuffer: SSBO,
mLineBufferBase: std.ArrayList(LineData),

pub fn Init(allocator: std.mem.Allocator) !Renderer2D {
    return Renderer2D{
        .mAllocator = allocator,
        .mQuadBuffer = SSBO.Init(@sizeOf(QuadData) * 100),
        .mQuadBufferBase = try std.ArrayList(QuadData).initCapacity(allocator, 100),
        .mCircleBuffer = SSBO.Init(@sizeOf(CircleData) * 100),
        .mCircleBufferBase = try std.ArrayList(CircleData).initCapacity(allocator, 100),
        .mLineBuffer = SSBO.Init(@sizeOf(LineData) * 100),
        .mLineBufferBase = try std.ArrayList(LineData).initCapacity(allocator, 100),
    };
}

pub fn Deinit(self: *Renderer2D) !void {
    self.mQuadBuffer.Deinit();
    self.mQuadBufferBase.deinit();
    self.mCircleBuffer.Deinit();
    self.mCircleBufferBase.deinit();
    self.mLineBuffer.Deinit();
    self.mLineBufferBase.deinit();
}

pub fn DrawQuad(self: *Renderer2D, transform: Mat4f32, color: Vec4f32, tex_coords: [4]Vec2f32, tex_index: f32, tiling_factor: f32) !void {
    const v_pos = LinAlg.Mat4MulMat4(transform, RectVertexPositions);
    try self.mQuadBufferBase.append(.{
        .Vertex1 = [3]f32{ v_pos[0][0], v_pos[0][1], v_pos[0][2] },
        .Vertex2 = [3]f32{ v_pos[1][0], v_pos[1][1], v_pos[1][2] },
        .Vertex3 = [3]f32{ v_pos[2][0], v_pos[2][1], v_pos[2][2] },
        .Vertex4 = [3]f32{ v_pos[3][0], v_pos[3][1], v_pos[3][2] },
        .Color = [4]f32{ color[0], color[1], color[2], color[3] },
        .TexCoord1 = [2]f32{ tex_coords[0][0], tex_coords[0][1] },
        .TexCoord2 = [2]f32{ tex_coords[1][0], tex_coords[1][1] },
        .TexCoord3 = [2]f32{ tex_coords[2][0], tex_coords[2][1] },
        .TexCoord4 = [2]f32{ tex_coords[3][0], tex_coords[3][1] },
        .TexIndex = tex_index,
        .TilingFactor = tiling_factor,
    });
}

pub fn DrawCircle(self: *Renderer2D, position: Vec3f32, rotation: Quatf32, radius: f32, color: Vec4f32) !void {
    try self.mCircleBufferBase.append(.{
        .Position = position,
        .Normal = LinAlg.NormalFromQuat(rotation),
        .Radius = radius,
        .Color = [4]f32{ color[0], color[1], color[2], color[3] },
    });
}

//TODO: FINISH DRAWING LINE
pub fn DrawLine(self: *Renderer2D, p1: Vec3f32, p2: Vec3f32, rotation: Quatf32, thickness: f32, color: Vec4f32) !void {
    const rot_norm = LinAlg.NormalFromQuat(rotation);
    const axis = LinAlg.NormalizeVec3(p1 - p2);

    try self.mLineBufferBase.append(.{
        .P1 = p1,
        .P2 = p2,
        .Normal = LinAlg.NormalizeVec3(rot_norm - @as(Vec3f32, @splat(LinAlg.Vec3DotVec3(rot_norm, axis))) * axis),
        .Thickness = thickness,
        .Color = color,
    });
}

pub fn BeginScene(self: *Renderer2D) void {
    self.mQuadBufferBase.clearRetainingCapacity();
    self.mCircleBufferBase.clearRetainingCapacity();
    self.mLineBufferBase.clearRetainingCapacity();
}
