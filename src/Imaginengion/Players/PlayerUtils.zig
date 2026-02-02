const EngineContext = @import("../Core/EngineContext.zig");
const Player = @import("Player.zig");
const PathType = @import("../Assets/Assets.zig").FileMetaData.PathType;
const PlayerComponents = @import("Components.zig");
const LensComponent = PlayerComponents.LensComponent;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");

//pub fn AddScriptToPlayer(engine_context: *EngineContext, player: Player, rel_path_script: []const u8, path_type: PathType) !void {
//    var new_script_handle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), rel_path_script, path_type);
//    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);
//
//    std.debug.assert(script_asset.mScriptType == .EntityInputPressed or script_asset.mScriptType == .EntityOnUpdate);
//
//    // Create the script component with the asset handle
//    const new_script_component = ScriptComponent{
//        .mScriptAssetHandle = new_script_handle,
//    };
//
//    const new_script_entity = try entity.AddChild(engine_context.EngineAllocator(), .Script);
//
//    _ = try new_script_entity.AddComponent(ScriptComponent, new_script_component);
//
//    // Add the appropriate script type component based on the script asset
//    switch (script_asset.mScriptType) {
//        .EntityInputPressed => {
//            _ = try new_script_entity.AddComponent(OnInputPressedScript, null);
//        },
//        .EntityOnUpdate => {
//            _ = try new_script_entity.AddComponent(OnUpdateScript, null);
//        },
//        else => @panic("this shouldnt happen!\n"),
//    }
//}

pub fn AddLensComponent(engine_context: *EngineContext, player: Player) LensComponent {
    var new_lens_component = LensComponent{};
    const engine_allocator = engine_context.EngineAllocator();

    new_lens_component.mViewportFrameBuffer = try FrameBuffer.Init(engine_allocator, &[_]TextureFormat{.RGBA8}, .None, 1, false, 1600, 900);
    new_lens_component.mViewportVertexArray = VertexArray.Init();
    new_lens_component.mViewportVertexBuffer = VertexBuffer.Init(@sizeOf([4][2]f32));
    new_lens_component.mViewportIndexBuffer = undefined;

    const shader_asset = engine_context.mRenderer.GetSDFShader();
    try new_lens_component.mViewportVertexBuffer.SetLayout(engine_context.EngineAllocator(), shader_asset.GetLayout());
    new_lens_component.mViewportVertexBuffer.SetStride(shader_asset.GetStride());

    var index_buffer_data = [6]u32{ 0, 1, 2, 2, 3, 0 };
    new_lens_component.mViewportIndexBuffer = IndexBuffer.Init(index_buffer_data[0..], 6);

    var data_vertex_buffer = [4][2]f32{ [2]f32{ -1.0, -1.0 }, [2]f32{ 1.0, -1.0 }, [2]f32{ 1.0, 1.0 }, [2]f32{ -1.0, 1.0 } };
    new_lens_component.mViewportVertexBuffer.SetData(&data_vertex_buffer[0][0], @sizeOf([4][2]f32), 0);
    try new_lens_component.mViewportVertexArray.AddVertexBuffer(engine_allocator, new_lens_component.mViewportVertexBuffer);
    new_lens_component.mViewportVertexArray.SetIndexBuffer(new_lens_component.mViewportIndexBuffer);

    new_lens_component.SetViewportSize(1600, 900);
    player.AddComponent(new_lens_component);
}
