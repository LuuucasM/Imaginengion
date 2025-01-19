const std = @import("std");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const Shader = @import("../Shaders/Shaders.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const Renderer2D = @This();

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Mat4f32 = LinAlg.Mat4f32;

pub const SpriteVertex = struct {
    Position: Vec3f32,
    Color: Vec4f32,
    TexCoord: Vec2f32,
    TexIndex: f32,
    TilingFactor: f32,
};

pub const CircleVertex = struct {
    Position: Vec3f32,
    LocalPosition: Vec3f32,
    Color: Vec4f32,
    Thickness: f32,
    Fade: f32,
};

pub const ELineVertex = struct {
    Position: Vec3f32,
    Color: Vec4f32,
};

const RectVertexPositions = Mat4f32{
    Vec4f32{ -0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, 0.5, 0.0, 1.0 },
    Vec4f32{ -0.5, 0.5, 0.0, 1.0 },
};

const RectTexCoordPositions = [4]Vec2f32{
    Vec2f32{ 0.0, 0.0 },
    Vec2f32{ 1.0, 0.0 },
    Vec2f32{ 1.0, 1.0 },
    Vec2f32{ 0.0, 1.0 },
};

mSpriteVertexArray: VertexArray,
mSpriteVertexBuffer: VertexBuffer,
mSpriteShader: Shader,

mCircleVertexArray: VertexArray,
mCircleVertexBuffer: VertexBuffer,
mCircleShader: Shader,

mELineVertexArray: VertexArray,
mELineVertexBuffer: VertexBuffer,
mELineShader: Shader,

mSpriteVertexCount: u32,
mSpriteVertexBufferBase: []SpriteVertex,
mSpriteVertexBufferPtr: *SpriteVertex,

mCircleVertexCount: u32,
mCircleVertexBufferBase: []CircleVertex,
mCircleVertexBufferPtr: *CircleVertex,

mELineVertexCount: u32,
mELineVertexBufferBase: []ELineVertex,
mELineVertexBufferPtr: *ELineVertex,

mCameraBuffer: Mat4f32,
mCameraUniformBuffer: UniformBuffer,

pub fn Init(
    max_vertices: u32,
    max_indices: u32,
    allocator: std.mem.Allocator,
) !Renderer2D {
    var new_renderer2d = Renderer2D{
        .mSpriteVertexArray = VertexArray.Init(allocator),
        .mSpriteVertexBuffer = VertexBuffer.Init(allocator, max_vertices * @sizeOf(SpriteVertex)),
        .mSpriteShader = try Shader.Init(allocator, "/assets/shaders/2d/Sprite.glsl"),

        .mCircleVertexArray = VertexArray.Init(allocator),
        .mCircleVertexBuffer = VertexBuffer.Init(allocator, max_vertices * @sizeOf(CircleVertex)),
        .mCircleShader = try Shader.Init(allocator, "/assets/shaders/2d/Circle.glsl"),

        .mELineVertexArray = VertexArray.Init(allocator),
        .mELineVertexBuffer = VertexBuffer.Init(allocator, max_vertices * @sizeOf(ELineVertex)),
        .mELineShader = try Shader.Init(allocator, "/assets/shaders/2d/ELine.glsl"),

        .mSpriteVertexCount = 0,
        .mSpriteVertexBufferBase = try allocator.alloc(SpriteVertex, max_vertices),
        .mSpriteVertexBufferPtr = undefined,

        .mCircleVertexCount = 0,
        .mCircleVertexBufferBase = try allocator.alloc(CircleVertex, max_vertices),
        .mCircleVertexBufferPtr = undefined,

        .mELineVertexCount = 0,
        .mELineVertexBufferBase = try allocator.alloc(ELineVertex, max_vertices),
        .mELineVertexBufferPtr = undefined,

        .mCameraBuffer = LinAlg.InitMat4CompTime(1.0),
        .mCameraUniformBuffer = UniformBuffer.Init(@sizeOf(Mat4f32), 0),
    };

    var rect_indices = try allocator.alloc(u32, max_indices);
    defer allocator.free(rect_indices);

    var i: usize = 0;
    var offset: u32 = 0;
    while (i < max_indices) : (i += 6) {
        rect_indices[i + 0] = offset + 0;
        rect_indices[i + 1] = offset + 1;
        rect_indices[i + 2] = offset + 2;

        rect_indices[i + 3] = offset + 2;
        rect_indices[i + 4] = offset + 3;
        rect_indices[i + 5] = offset + 0;

        offset += 4;
    }

    const rect_index_buffer = IndexBuffer.Init(rect_indices, max_indices);

    //sprite
    try new_renderer2d.mSpriteVertexBuffer.SetLayout(new_renderer2d.mSpriteShader.GetLayout());
    new_renderer2d.mSpriteVertexBuffer.SetStride(new_renderer2d.mSpriteShader.GetStride());

    try new_renderer2d.mSpriteVertexArray.AddVertexBuffer(new_renderer2d.mSpriteVertexBuffer);

    new_renderer2d.mSpriteVertexArray.SetIndexBuffer(rect_index_buffer);

    new_renderer2d.mSpriteVertexBufferPtr = &new_renderer2d.mSpriteVertexBufferBase[0];

    //circle
    try new_renderer2d.mCircleVertexBuffer.SetLayout(new_renderer2d.mCircleShader.GetLayout());
    new_renderer2d.mCircleVertexBuffer.SetStride(new_renderer2d.mCircleShader.GetStride());

    try new_renderer2d.mCircleVertexArray.AddVertexBuffer(new_renderer2d.mCircleVertexBuffer);

    new_renderer2d.mCircleVertexArray.SetIndexBuffer(rect_index_buffer);

    new_renderer2d.mCircleVertexBufferPtr = &new_renderer2d.mCircleVertexBufferBase[0];

    //editor line
    try new_renderer2d.mELineVertexBuffer.SetLayout(new_renderer2d.mELineShader.GetLayout());
    new_renderer2d.mELineVertexBuffer.SetStride(new_renderer2d.mELineShader.GetStride());

    try new_renderer2d.mELineVertexArray.AddVertexBuffer(new_renderer2d.mELineVertexBuffer);

    new_renderer2d.mELineVertexArray.SetIndexBuffer(rect_index_buffer);

    new_renderer2d.mELineVertexBufferPtr = &new_renderer2d.mELineVertexBufferBase[0];

    return new_renderer2d;
}

pub fn DrawSprite(self: Renderer2D, transform: Mat4f32, color: Vec4f32, texture_index: f32, tiling_factor: f32) void {
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        self.mSpriteVertexBufferPtr.Position = LinAlg.Mat4MulVec4(transform, RectVertexPositions[i]);
        self.mSpriteVertexBufferPtr.Color = color;
        self.mSpriteVertexBufferPtr.TexCoord = RectVertexPositions[i];
        self.mSpriteVertexBufferPtr.TexIndex = texture_index;
        self.mSpriteVertexBufferPtr.TilingFactor = tiling_factor;
        self.mSpriteVertexBufferPtr += 1;
    }
    self.mSpriteVertexCount += 6;
}
pub fn DrawCircle(self: Renderer2D, transform: Mat4f32, color: Vec4f32, thickness: f32, fade: f32) void {
    var i: usize = 0;

    while (i < 4) : (i += 1) {
        self.mCircleVertexBufferPtr.Position = LinAlg.Mat4MulVec4(transform, RectVertexPositions[i]);
        const local_pos = RectVertexPositions[i] * @as(Vec4f32, @splat(2.0));
        self.mCircleVertexBufferPtr.LocalPosition = Vec3f32{ local_pos[0], local_pos[1], local_pos[2] };
        self.mCircleVertexBufferPtr.Color = color;
        self.mCircleVertexBufferPtr.Thickness = thickness;
        self.mCircleVertexBufferPtr.Fade = fade;
        self.mCircleVertexBufferPtr += 1;
    }
    self.mCircleVertexCount += 6;
}

pub fn DrawELine(self: Renderer2D, p0: Vec3f32, p1: Vec3f32, color: Vec4f32) void {
    self.mELineVertexBufferPtr.Position = p0;
    self.mELineVertexBufferPtr.Color = color;
    self.mELineVertexBufferPtr += 1;

    self.mELineVertexBufferPtr.Position = p1;
    self.mELineVertexBufferPtr.Color = color;
    self.mELineVertexBufferPtr += 1;

    self.mELineVertexCount += 2;
}

pub fn StartBatchSprite(self: Renderer2D) void {
    self.mSpriteVertexCount = 0;
    self.mSpriteVertexBufferPtr = &self.mSpriteVertexBufferBase[0];
}

pub fn StartBatchCircle(self: Renderer2D) void {
    self.mCircleVertexCount = 0;
    self.mCircleVertexBufferPtr = &self.mCircleVertexBufferBase[0];
}

pub fn StartBatchELine(self: Renderer2D) void {
    self.mELineVertexCount = 0;
    self.mELineVertexBufferPtr = &self.mELineVertexBufferBase[0];
}

pub fn FlushSprite(self: Renderer2D) void {
    const data_size: u32 = @intFromPtr(self.mSpriteVertexBufferPtr) - @intFromPtr(self.mSpriteVertexBufferBase);
    self.mSpriteVertexBuffer.SetData(self.mSpriteVertexBufferBase, data_size);
    self.mSpriteShader.Bind();
}

pub fn FlushCircle(self: Renderer2D) void {
    const data_size: u32 = @intFromPtr(self.mCircleVertexBufferPtr) - @intFromPtr(self.mCircleVertexBufferBase);
    self.mCircleVertexBuffer.SetData(self.mCircleVertexBufferBase, data_size);
    self.mCircleShader.Bind();
}

pub fn FlushELine(self: Renderer2D) void {
    const data_size: u32 = @intFromPtr(self.mELineVertexBufferPtr) - @intFromPtr(self.mELineVertexBufferBase);
    self.mELineVertexBuffer.SetData(self.mELineVertexBufferBase, data_size);
    self.mELineShader.Bind();
}
