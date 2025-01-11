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

const Stats = struct {
    mDrawCalls: u32,
    mTriCount: u32,
};

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

mSpriteVertexArray: VertexArray,
mSpriteVertexBuffer: VertexBuffer,
mSpriteShader: Shader,

mCircleVertexArray: VertexArray,
mCircleVertexBuffer: VertexBuffer,
mCircleShader: Shader,

mELineVertexArray: VertexArray,
mELineVertexBuffer: VertexBuffer,
mELineShader: Shader,

mWhiteTexutre: AssetHandle,

mSpriteIndexCount: u32,
mSpriteVertexBufferBase: []SpriteVertex,
mSpriteVertexBufferPtr: []SpriteVertex,

mCircleIndexCount: u32,
mCircleVertexBufferBase: []CircleVertex,
mCircleVertexBufferPtr: []CircleVertex,

mELineIndexCount: u32,
mELineVertexBufferBase: []ELineVertex,
mELineVertexBufferPtr: []ELineVertex,

mELineThickness: f32,

mTextureSlots: std.ArrayList(AssetHandle),
mTextureSlotIndex: u32,

mRectVertexPositions: Mat4f32,

mCameraUniformBuffer: UniformBuffer,

pub fn Init(
    max_vertices: u32,
    max_indices: u32,
    max_texture_image_slots: u32,
    allocator: std.mem.Allocator,
) !Renderer2D {
    const new_renderer2d = Renderer2D{
        .mSpriteVertexArray = VertexArray.Init(allocator),
        .mSpriteVertexBuffer = VertexBuffer.Init(allocator, max_vertices * @sizeOf(SpriteVertex)),
        .mSpriteShader = Shader.Init(allocator, "/assets/shaders/2d/Sprite.glsl"),

        .mCircleVertexArray = VertexArray.Init(allocator),
        .mCircleVertexBuffer = VertexBuffer.Init(allocator, max_vertices * @sizeOf(CircleVertex)),
        .mCircleShader = Shader.Init(allocator, "/assets/shaders/2d/Circle.glsl"),

        .mELineVertexArray = VertexArray.Init(allocator),
        .mELineVertexBuffer = VertexBuffer.Init(allocator, max_vertices * @sizeOf(ELineVertex)),
        .mELineShader = Shader.Init(allocator, "/assets/shaders/2d/ELine.glsl"),

        .mWhiteTexutre = AssetManager.GetAssetHandleRef("/assets/textures/whitetexture.png"),

        .mSpriteIndexCount = 0,
        .mSpriteVertexBufferBase = try allocator.alloc(SpriteVertex, max_vertices),
        .mSpriteVertexBufferPtr = undefined,

        .mCircleIndexCount = 0,
        .mCircleVertexBufferBase = try allocator.alloc(CircleVertex, max_vertices),
        .mCircleVertexBufferPtr = undefined,

        .mELineIndexCount = 0,
        .mELineVertexBufferBase = try allocator.alloc(ELineVertex, max_vertices),
        .mELineVertexBufferPtr = undefined,

        .mELineThickness = 2.0,

        .mTextureSlots = std.ArrayList(AssetHandle).initCapacity(allocator, max_texture_image_slots),
        .mTextureSlotIndex = 1,

        .mRectVertexPositions = Mat4f32{
            Vec4f32{ -0.5, -0.5, 0.0, 1.0 },
            Vec4f32{ 0.5, -0.5, 0.0, 1.0 },
            Vec4f32{ 0.5, 0.5, 0.0, 1.0 },
            Vec4f32{ -0.5, 0.5, 0.0, 1.0 },
        },

        .mCameraUniformBuffer = UniformBuffer.Init(@sizeOf(Mat4f32), 0),
    };

    var rect_indices = try allocator.alloc(u32, max_indices);
    defer allocator.free(rect_indices);

    var i: usize = 0;
    var offset: usize = 0;
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
    new_renderer2d.mSpriteVertexBuffer.SetLayout(new_renderer2d.mSpriteShader.GetLayout());
    new_renderer2d.mSpriteVertexBuffer.SetStride(new_renderer2d.mSpriteShader.GetStride());

    new_renderer2d.mSpriteVertexArray.AddVertexBuffer(new_renderer2d.mSpriteVertexBuffer);

    new_renderer2d.mSpriteVertexArray.SetIndexBuffer(rect_index_buffer);

    new_renderer2d.mSpriteVertexBufferPtr = new_renderer2d.mSpriteVertexBufferBase;

    //circle
    new_renderer2d.mCircleVertexBuffer.SetLayout(new_renderer2d.mCircleShader.GetLayout());
    new_renderer2d.mCircleVertexBuffer.SetStride(new_renderer2d.mCircleShader.GetStride());

    new_renderer2d.mCircleVertexArray.AddVertexBuffer(new_renderer2d.mCircleVertexBuffer);

    new_renderer2d.mCircleVertexArray.SetIndexBuffer(rect_index_buffer);

    new_renderer2d.mCircleVertexBufferPtr = new_renderer2d.mCircleVertexBufferBase;

    //editor line
    new_renderer2d.mELineVertexBuffer.SetLayout(new_renderer2d.mELineShader.GetLayout());
    new_renderer2d.mELineVertexBuffer.SetStride(new_renderer2d.mELineShader.GetStride());

    new_renderer2d.mELineVertexArray.AddVertexBuffer(new_renderer2d.mELineVertexBuffer);

    new_renderer2d.mELineVertexArray.SetIndexBuffer(rect_index_buffer);

    new_renderer2d.mELineVertexBufferPtr = new_renderer2d.mELineVertexBufferBase;

    return new_renderer2d;
}
