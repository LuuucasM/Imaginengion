const std = @import("std");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const Shader = @import("../Shaders/Shaders.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const Renderer2D = @This();

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Mat4f32 = LinAlg.Mat4f32;
const MAX_PATH_LEN = 256;

pub const SpriteVertex = extern struct {
    Position: [3]f32,
    Color: [4]f32,
    TexCoord: [2]f32,
    TexIndex: f32,
    TilingFactor: f32,
};

pub const CircleVertex = extern struct {
    Position: [3]f32,
    Color: [4]f32,
    LocalPosition: [3]f32,
    Thickness: f32,
    Fade: f32,
};

pub const ELineVertex = extern struct {
    Position: [3]f32,
    Color: [4]f32,
};

const RectVertexPositions = Mat4f32{
    Vec4f32{ -0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, 0.5, 0.0, 1.0 },
    Vec4f32{ -0.5, 0.5, 0.0, 1.0 },
};

mAllocator: std.mem.Allocator,

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
mSpriteIndexCount: u32,
mSpriteVertexBufferBase: []SpriteVertex,
mSpriteVertexBufferPtr: *SpriteVertex,

mCircleVertexCount: u32,
mCircleIndexCount: u32,
mCircleVertexBufferBase: []CircleVertex,
mCircleVertexBufferPtr: *CircleVertex,

mELineVertexCount: u32,
mELineVertexBufferBase: []ELineVertex,
mELineVertexBufferPtr: *ELineVertex,

mRectIndexBuffer: IndexBuffer,

pub fn Init(
    max_vertices: u32,
    max_indices: u32,
    allocator: std.mem.Allocator,
) !Renderer2D {
    var new_renderer2d = Renderer2D{
        .mAllocator = allocator,

        .mSpriteVertexArray = VertexArray.Init(allocator),
        .mSpriteVertexBuffer = VertexBuffer.Init(allocator, max_vertices * @sizeOf(SpriteVertex)),
        .mSpriteShader = try Shader.Init(allocator, "assets/shaders/2d/Sprite.glsl"),

        .mCircleVertexArray = VertexArray.Init(allocator),
        .mCircleVertexBuffer = VertexBuffer.Init(allocator, max_vertices * @sizeOf(CircleVertex)),
        .mCircleShader = try Shader.Init(allocator, "assets/shaders/2d/Circle.glsl"),

        .mELineVertexArray = VertexArray.Init(allocator),
        .mELineVertexBuffer = VertexBuffer.Init(allocator, max_vertices * @sizeOf(ELineVertex)),
        .mELineShader = try Shader.Init(allocator, "assets/shaders/2d/ELine.glsl"),

        .mRectIndexBuffer = undefined,

        .mSpriteVertexCount = 0,
        .mSpriteIndexCount = 0,
        .mSpriteVertexBufferBase = try allocator.alignedAlloc(SpriteVertex, @alignOf(SpriteVertex), max_vertices),
        .mSpriteVertexBufferPtr = undefined,

        .mCircleVertexCount = 0,
        .mCircleIndexCount = 0,
        .mCircleVertexBufferBase = try allocator.alignedAlloc(CircleVertex, @alignOf(CircleVertex), max_vertices),
        .mCircleVertexBufferPtr = undefined,

        .mELineVertexCount = 0,
        .mELineVertexBufferBase = try allocator.alignedAlloc(ELineVertex, @alignOf(ELineVertex), max_vertices),
        .mELineVertexBufferPtr = undefined,
    };

    var rect_indices = try allocator.alignedAlloc(u32, @alignOf(u32), max_indices);
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

    new_renderer2d.mRectIndexBuffer = IndexBuffer.Init(rect_indices, max_indices * @sizeOf(u32));

    //sprite
    try new_renderer2d.mSpriteVertexBuffer.SetLayout(new_renderer2d.mSpriteShader.GetLayout());
    new_renderer2d.mSpriteVertexBuffer.SetStride(new_renderer2d.mSpriteShader.GetStride());

    try new_renderer2d.mSpriteVertexArray.AddVertexBuffer(new_renderer2d.mSpriteVertexBuffer);

    new_renderer2d.mSpriteVertexArray.SetIndexBuffer(new_renderer2d.mRectIndexBuffer);

    new_renderer2d.mSpriteVertexBufferPtr = &new_renderer2d.mSpriteVertexBufferBase[0];

    //circle
    try new_renderer2d.mCircleVertexBuffer.SetLayout(new_renderer2d.mCircleShader.GetLayout());
    new_renderer2d.mCircleVertexBuffer.SetStride(new_renderer2d.mCircleShader.GetStride());

    try new_renderer2d.mCircleVertexArray.AddVertexBuffer(new_renderer2d.mCircleVertexBuffer);

    new_renderer2d.mCircleVertexArray.SetIndexBuffer(new_renderer2d.mRectIndexBuffer);

    new_renderer2d.mCircleVertexBufferPtr = &new_renderer2d.mCircleVertexBufferBase[0];

    //editor line
    try new_renderer2d.mELineVertexBuffer.SetLayout(new_renderer2d.mELineShader.GetLayout());
    new_renderer2d.mELineVertexBuffer.SetStride(new_renderer2d.mELineShader.GetStride());

    try new_renderer2d.mELineVertexArray.AddVertexBuffer(new_renderer2d.mELineVertexBuffer);

    new_renderer2d.mELineVertexArray.SetIndexBuffer(new_renderer2d.mRectIndexBuffer);

    new_renderer2d.mELineVertexBufferPtr = &new_renderer2d.mELineVertexBufferBase[0];

    return new_renderer2d;
}

pub fn Deinit(self: *Renderer2D) void {
    self.mSpriteVertexBuffer.Deinit();
    self.mSpriteVertexArray.Deinit();
    self.mSpriteShader.Deinit();

    self.mCircleVertexBuffer.Deinit();
    self.mCircleVertexArray.Deinit();
    self.mCircleShader.Deinit();

    self.mELineVertexBuffer.Deinit();
    self.mELineVertexArray.Deinit();
    self.mELineShader.Deinit();

    self.mRectIndexBuffer.Deinit();

    self.mAllocator.free(self.mSpriteVertexBufferBase);
    self.mAllocator.free(self.mCircleVertexBufferBase);
    self.mAllocator.free(self.mELineVertexBufferBase);
}

pub fn DrawSprite(self: *Renderer2D, transform: Mat4f32, color: Vec4f32, texture_index: f32, tiling_factor: f32, tex_coords: [4]Vec2f32) void {
    var i: usize = 0;
    const positions = LinAlg.Mat4MulMat4(transform, RectVertexPositions);
    while (i < 4) : (i += 1) {
        self.mSpriteVertexBufferPtr.*.Position = [3]f32{ positions[i][0], positions[i][1], positions[i][2] };
        self.mSpriteVertexBufferPtr.*.Color = [4]f32{ color[0], color[1], color[2], color[3] };
        self.mSpriteVertexBufferPtr.*.TexCoord = [2]f32{ tex_coords[i][0], tex_coords[i][1] };
        self.mSpriteVertexBufferPtr.*.TexIndex = texture_index;
        self.mSpriteVertexBufferPtr.*.TilingFactor = tiling_factor;
        self.mSpriteVertexCount += 1;
        self.mSpriteVertexBufferPtr = &self.mSpriteVertexBufferBase[self.mSpriteVertexCount];
    }
    self.mSpriteIndexCount += 6;
}
pub fn DrawCircle(self: *Renderer2D, transform: Mat4f32, color: Vec4f32, thickness: f32, fade: f32) void {
    var i: usize = 0;
    const positions = LinAlg.Mat4MulMat4(transform, RectVertexPositions);
    while (i < 4) : (i += 1) {
        self.mCircleVertexBufferPtr.Position = [3]f32{ positions[i][0], positions[i][1], positions[i][2] };
        self.mCircleVertexBufferPtr.Color = [4]f32{ color[0], color[1], color[2], color[3] };
        const local_pos = RectVertexPositions[i] * @as(Vec4f32, @splat(2.0));
        self.mCircleVertexBufferPtr.LocalPosition = [3]f32{ local_pos[0], local_pos[1], local_pos[2] };
        self.mCircleVertexBufferPtr.Thickness = thickness;
        self.mCircleVertexBufferPtr.Fade = fade;
        self.mCircleVertexCount += 1;
        self.mCircleVertexBufferPtr = &self.mCircleVertexBufferBase[self.mCircleVertexCount];
    }

    self.mCircleIndexCount += 6;
}

pub fn DrawELine(self: *Renderer2D, p0: Vec3f32, p1: Vec3f32, color: Vec4f32) void {
    self.mELineVertexBufferPtr.Position = [3]f32{ p0[0], p0[1], p0[2] };
    self.mELineVertexBufferPtr.Color = [4]f32{ color[0], color[1], color[2], color[3] };
    self.mELineVertexBufferPtr += 1;

    self.mELineVertexBufferPtr.Position = [3]f32{ p1[0], p1[1], p1[2] };
    self.mELineVertexBufferPtr.Color = [4]f32{ color[0], color[1], color[2], color[3] };
    self.mELineVertexBufferPtr += 1;

    self.mELineVertexCount += 2;
}

pub fn BeginScene(self: *Renderer2D) void {
    self.mSpriteVertexCount = 0;
    self.mSpriteIndexCount = 0;
    self.mSpriteVertexBufferPtr = &self.mSpriteVertexBufferBase[0];

    self.mCircleVertexCount = 0;
    self.mCircleIndexCount = 0;
    self.mCircleVertexBufferPtr = &self.mCircleVertexBufferBase[0];

    self.mELineVertexCount = 0;
    self.mELineVertexBufferPtr = &self.mELineVertexBufferBase[0];
}

pub fn FlushSprite(self: Renderer2D) void {
    const data_size: usize = @sizeOf(SpriteVertex) * self.mSpriteVertexCount;
    self.mSpriteVertexBuffer.SetData(self.mSpriteVertexBufferBase.ptr, data_size);
    self.mSpriteShader.Bind();
    self.mSpriteVertexArray.Bind();
}

pub fn FlushCircle(self: Renderer2D) void {
    const data_size: usize = @sizeOf(CircleVertex) * self.mSpriteVertexCount;
    self.mCircleVertexBuffer.SetData(self.mCircleVertexBufferBase.ptr, data_size);
    self.mCircleShader.Bind();
    self.mCircleVertexArray.Bind();
}

pub fn FlushELine(self: Renderer2D) void {
    const data_size: usize = @sizeOf(ELineVertex) * self.mSpriteVertexCount;
    self.mELineVertexBuffer.SetData(self.mELineVertexBufferBase.ptr, data_size);
    self.mELineShader.Bind();
    self.mELineVertexArray.Bind();
}
