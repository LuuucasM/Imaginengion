const std = @import("std");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const Window = @import("../Windows/Window.zig");

const Renderer2D = @import("Renderer2D.zig");
const Renderer3D = @import("Renderer3D.zig");

const ShaderAsset = @import("../Assets/Assets.zig").ShaderAsset;
const AssetHandle = @import("../Assets/AssetHandle.zig");

const SceneManager = @import("../Scene/SceneManager.zig");

const Entity = @import("../GameObjects/Entity.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const TransformComponent = EntityComponents.TransformComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const EngineContext = @import("../Core/EngineContext.zig");
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig").FrameBuffer;
const TextureFormat = @import("../Assets/Assets.zig").Texture2D.TextureFormat;
const RenderPlatform = @import("RenderPlatform.zig");
const PushConstants = @import("RenderPlatform.zig").PushConstants;

const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Tracy = @import("../Core/Tracy.zig");

const Renderer = @This();

pub const OutputFrameBuffer = FrameBuffer(&[_]TextureFormat{.RGBA8}, .None, 1);

mPlatform: RenderPlatform = .{},

mR2D: Renderer2D = .{},
mR3D: Renderer3D = .{},

mPushConstants: PushConstants = .{
    .aspect_ratio = 0,
    .fov = 90,
    .glyphs_count = 0,
    .mode = 1,
    .perspective_far = 1000,
    .position = [3]f32{ 0, 0, 0 },
    .quads_count = 0,
    .resolution_height = 0,
    .resolution_width = 0,
    .rotation = [4]f32{ 1, 0, 0, 0 },
},

mSDFShader: AssetHandle = .{},

pub fn Init(self: *Renderer, engine_context: *EngineContext) !void {
    const engine_allocator = engine_context.EngineAllocator();

    const shader_rel_path = "assets/shaders/SDFShader.program";
    self.mSDFShader = try engine_context.mAssetManager.GetAssetHandleRef(engine_allocator, .{ .File = .{ .rel_path = shader_rel_path, .path_type = .Eng } });

    self.mPlatform.Init(engine_context, try self.mSDFShader.GetAsset(engine_context, ShaderAsset));

    try self.mR2D.Init(engine_context);
    self.mR3D.Init();
}

pub fn Deinit(self: *Renderer, engine_context: *EngineContext) void {
    self.mPlatform.Deinit(engine_context.mAppWindow);

    self.mSDFShader.ReleaseAsset();

    self.mR2D.Deinit(engine_context.EngineAllocator());
    self.mR3D.Deinit(engine_context.EngineAllocator());
}

//mode bit 0: set to 1 for aspect ratio correction, 0 for not
pub fn OnUpdate(self: *Renderer, world_type: EngineContext.WorldType, engine_context: *EngineContext, push_constants: PushConstants, frame_buffer: *OutputFrameBuffer) !void {
    const zone = Tracy.ZoneInit("Renderer::OnUpdate", @src());
    defer zone.Deinit();
    self.mPlatform.PushDebugGroup("Frame\x00");
    defer self.mPlatform.PopDebugGroup();

    if (!self.mPlatform.BeginFrame(engine_context.mAppWindow)) return;

    const scene_manager = switch (world_type) {
        .Game => &engine_context.mGameWorld,
        .Editor => &engine_context.mEditorWorld,
        .Simulate => &engine_context.mSimulateWorld,
    };

    self.BeginRendering(engine_context.EngineAllocator());

    //get all the shapes
    const shapes_ids = try scene_manager.GetEntityGroup(
        engine_context.FrameAllocator(),
        GroupQuery{
            .Or = &[_]GroupQuery{
                GroupQuery{ .Component = QuadComponent },
                GroupQuery{ .Component = TextComponent },
            },
        },
    );

    switch (world_type) {
        .Game => engine_context.mEngineStats.GameWorldStats.mRenderStats.TotalObjects = shapes_ids.items.len,
        .Editor => engine_context.mEngineStats.EditorWorldStats.mRenderStats.TotalObjects = shapes_ids.items.len,
        .Simulate => engine_context.mEngineStats.SimulateWorldStats.mRenderStats.TotalObjects = shapes_ids.items.len,
    }

    //TODO: culling
    //TODO: sorting
    //TODO: other optimizsations?

    for (shapes_ids.items) |shape_id| {
        const shape_entity = scene_manager.GetEntity(shape_id);
        try self.DrawShape(engine_context, shape_entity);
    }

    push_constants.quads_count = self.mR2D.mQuadBufferBase.items.len;
    push_constants.glyphs_count = self.mR2D.mGlyphBufferBase.items.len;

    try self.EndRendering(world_type, engine_context, frame_buffer, &push_constants);
}

pub fn GetSDFShader(self: *Renderer, engine_context: *EngineContext) *ShaderAsset {
    return try self.mSDFShader.GetAsset(engine_context, ShaderAsset);
}

fn BeginRendering(self: *Renderer, engine_allocator: std.mem.Allocator) void {
    const zone = Tracy.ZoneInit("BeginFrame", @src());
    defer zone.Deinit();

    self.mPlatform.PushDebugGroup("Set Camera Data\x00");
    defer self.mPlatform.PopDebugGroup();

    self.mR2D.StartBatch(engine_allocator);
}

fn DrawShape(self: *Renderer, engine_context: *EngineContext, entity: Entity) anyerror!void {
    const zone = Tracy.ZoneInit("Renderer Draw Shape", @src());
    defer zone.Deinit();

    const transform_component = entity.GetComponent(TransformComponent).?;

    //check for specific shapes and draw them if they exist
    if (entity.GetComponent(QuadComponent)) |quad_component| {
        try self.mR2D.DrawQuad(engine_context, transform_component, quad_component);
    }
    if (entity.GetComponent(TextComponent)) |text_component| {
        try self.mR2D.DrawText(engine_context, transform_component, text_component);
    }
}

fn EndRendering(self: *Renderer, world_type: EngineContext.WorldType, engine_context: *EngineContext, frame_buffer: *OutputFrameBuffer, push_constants: *PushConstants) !void {
    const zone = Tracy.ZoneInit("Renderer EndRendering", @src());
    defer zone.Deinit();

    self.mPlatform.PushDebugGroup("End Rendering\x00");
    defer self.mPlatform.PopDebugGroup();

    const cmd = self.mPlatform.GetCommandBuff();

    self.mR2D.SetBuffers(world_type, engine_context);

    self.mPlatform.PushDebugGroup("Draw\x00");
    defer self.mPlatform.PopDebugGroup();

    const render_pass = frame_buffer.BeginRenderPass(engine_context, .{ 0.3, 0.3, 0.3, 1.0 });
    defer frame_buffer.EndRenderPass(render_pass);

    self.mPlatform.Draw(cmd, push_constants);

    self.mPlatform.EndFrame();
}
