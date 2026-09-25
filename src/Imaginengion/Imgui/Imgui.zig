const std = @import("std");
const Application = @import("../Core/Application.zig");
const Window = @import("../Windows/Window.zig");
const imgui = @import("../Core/CImports.zig").imgui;
const sdl = @import("../Core/CImports.zig").sdl;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Texture2D = @import("../ECSComponents/AComponents.zig").Texture2D;
const TextureManager = @import("../TextureManager/TextureManager.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const NameComponent = @import("../ECSComponents/EComponents.zig").NameComponent;
const ImguiManager = @This();

/// Drag drop payload ID for an Entity value, set by the ECS display and accepted by RenderEntityRef
pub const ENTITY_REF_PAYLOAD = "EntityRef";

const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Vec2 = MathTypes.Vec2;
const Quat = MathTypes.Quat;

const TEXTURE_SIZE: usize = 128;

mImguiTextures: std.ArrayList(*sdl.SDL_GPUTexture) = .empty,
mNumUsedTextures: usize = 0,

pub fn Init(_: *ImguiManager, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("ImguiManager::Init", @src());
    defer zone.Deinit();
    _ = imgui.igCreateContext(null);
    const io = imgui.igGetIO_Nil();
    io.*.ConfigFlags |= imgui.ImGuiConfigFlags_NavEnableKeyboard; // Enable Keyboard Controls
    io.*.ConfigFlags |= imgui.ImGuiConfigFlags_NavEnableGamepad; // Enable Gamepad Controls
    io.*.ConfigFlags |= imgui.ImGuiConfigFlags_DockingEnable; // Enable Docking
    //io.*.ConfigFlags |= imgui.ImGuiConfigFlags_ViewportsEnable; // Enable Multi-Viewport / Platform Windows

    const style: *imgui.struct_ImGuiStyle = imgui.igGetStyle();

    imgui.igStyleColorsDark(style);
    //imgui.igStyleColorsLight(style);

    // When viewports are enabled we tweak WindowRounding/WindowBg so platform windows can look identical to regular ones.
    if ((io.*.ConfigFlags & imgui.ImGuiConfigFlags_ViewportsEnable) > 0) {
        style.*.WindowRounding = 0.0;
        style.*.Colors[imgui.ImGuiCol_WindowBg].w = 1.0;
    }

    SetDarkThemeColors(style);

    const device: ?*sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());
    const win: ?*sdl.SDL_Window = @ptrCast(engine_context.mAppWindow.GetNativeWindow());

    _ = imgui.ImGui_ImplSDL3_InitForSDLGPU(@ptrCast(win));

    var init_info = imgui.ImGui_ImplSDLGPU3_InitInfo{
        .Device = @ptrCast(device),
        .ColorTargetFormat = sdl.SDL_GetGPUSwapchainTextureFormat(device, @ptrCast(win)),
        .MSAASamples = sdl.SDL_GPU_SAMPLECOUNT_1,
        .SwapchainComposition = sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
        .PresentMode = sdl.SDL_GPU_PRESENTMODE_VSYNC,
    };
    _ = imgui.ImGui_ImplSDLGPU3_Init(@ptrCast(&init_info));
}
pub fn Deinit(self: *ImguiManager, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("ImguiManager::Deinit", @src());
    defer zone.Deinit();

    const device: ?*sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());

    _ = sdl.SDL_WaitForGPUIdle(device);
    imgui.ImGui_ImplSDL3_Shutdown();
    imgui.ImGui_ImplSDLGPU3_Shutdown();
    imgui.igDestroyContext(null);

    for (self.mImguiTextures.items) |tex| {
        _ = sdl.SDL_ReleaseGPUTexture(device, tex);
    }

    self.mImguiTextures.deinit(engine_context.EngineAllocator());
}

pub fn ProcessEvent(_: *ImguiManager, event: *sdl.SDL_Event) void {
    _ = imgui.ImGui_ImplSDL3_ProcessEvent(@ptrCast(event));
}
pub fn Begin(self: *ImguiManager) void {
    const zone = Tracy.ZoneInit("ImguiManager::Begin", @src());
    defer zone.Deinit();
    imgui.ImGui_ImplSDLGPU3_NewFrame();
    imgui.ImGui_ImplSDL3_NewFrame();
    imgui.igNewFrame();
    self.mNumUsedTextures = 0;
}
pub fn End(_: ImguiManager, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("ImguiManager::End", @src());
    defer zone.Deinit();

    const io: *imgui.ImGuiIO = imgui.igGetIO_Nil();

    imgui.igRender();
    const draw_data = imgui.igGetDrawData();

    const cmd_buffer = engine_context.mRenderer.mPlatform.GetFrameCmdBuff();
    const swapchain_texture = engine_context.mRenderer.mPlatform.GetSwapchain();

    imgui.ImGui_ImplSDLGPU3_PrepareDrawData(draw_data, @ptrCast(cmd_buffer));

    const target_info = sdl.SDL_GPUColorTargetInfo{
        .texture = @ptrCast(swapchain_texture),
        .clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 1.0 },
        .load_op = sdl.SDL_GPU_LOADOP_LOAD, // was CLEAR
        .store_op = sdl.SDL_GPU_STOREOP_STORE,
        .mip_level = 0,
        .layer_or_depth_plane = 0,
        .cycle = false,
        .resolve_texture = null,
        .resolve_mip_level = 0,
        .resolve_layer = 0,
        .cycle_resolve_texture = false,
        .padding1 = 0,
        .padding2 = 0,
    };

    const render_pass = sdl.SDL_BeginGPURenderPass(@ptrCast(cmd_buffer), &target_info, 1, null);
    imgui.ImGui_ImplSDLGPU3_RenderDrawData(draw_data, @ptrCast(cmd_buffer), @ptrCast(render_pass), null);
    sdl.SDL_EndGPURenderPass(render_pass);

    if (io.ConfigFlags & imgui.ImGuiConfigFlags_ViewportsEnable != 0) {
        imgui.igUpdatePlatformWindows();
        imgui.igRenderPlatformWindowsDefault(null, null);
    }
}

pub fn GetImguiTexture(self: *ImguiManager, engine_context: *EngineContext, texture: *Texture2D) !imgui.struct_ImTextureRef_c {
    const device: *sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());

    const preview = try self.getOrCreatePreviewTexture(engine_context.EngineAllocator(), device);
    const texture_handle = texture.GetTextureHandle();
    const bin_index = TextureManager.GetBinIndex(texture_handle);
    const slot_index = TextureManager.GetSlotIndex(texture_handle);
    const offset_x, const offset_y = TextureManager.GetPixelOffsets(bin_index, slot_index);
    const layer = TextureManager.GetLayerIndex(texture_handle);

    const copy_w = @min(texture.GetWidth(), TEXTURE_SIZE);
    const copy_h = @min(texture.GetHeight(), TEXTURE_SIZE);

    const dst_x = (TEXTURE_SIZE - copy_w) / 2;
    const dst_y = (TEXTURE_SIZE - copy_h) / 2;

    const cmd = sdl.SDL_AcquireGPUCommandBuffer(device) orelse return error.AquireGPUCMDFailed;
    defer _ = sdl.SDL_SubmitGPUCommandBuffer(cmd);

    const copy_pass = sdl.SDL_BeginGPUCopyPass(cmd);
    defer sdl.SDL_EndGPUCopyPass(copy_pass);

    const atlas_texture: *sdl.SDL_GPUTexture = @ptrCast(texture.GetTexture());

    const src = sdl.SDL_GPUTextureLocation{
        .texture = atlas_texture,
        .mip_level = 0,
        .layer = @intCast(layer),
        .x = @intCast(offset_x),
        .y = @intCast(offset_y),
        .z = 0,
    };

    const dst = sdl.SDL_GPUTextureLocation{
        .texture = preview,
        .mip_level = 0,
        .layer = 0,
        .x = @intCast(dst_x),
        .y = @intCast(dst_y),
        .z = 0,
    };

    sdl.SDL_CopyGPUTextureToTexture(
        copy_pass,
        &src,
        &dst,
        copy_w,
        copy_h,
        1,
        true,
    );

    return imgui.struct_ImTextureRef_c{
        ._TexID = @as(imgui.ImTextureID, @intFromPtr(preview)),
        ._TexData = null,
    };
}

pub fn RenderVec3(vec: *Vec3(f32), label: []const u8, reset_value: f32, speed: f32, column_width: f32) !void {
    const io = imgui.igGetIO_Nil();
    const bold_font = io.*.Fonts.*.Fonts.Data[0];
    imgui.igPushID_Str(label.ptr);
    defer imgui.igPopID();

    imgui.igColumns(2, 0, false);
    defer imgui.igColumns(1, 0, false);
    imgui.igSetColumnWidth(0, column_width);
    imgui.igText(label.ptr);
    imgui.igNextColumn();

    imgui.igPushMultiItemsWidths(3, imgui.igCalcItemWidth());
    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_ItemSpacing, .{ .x = 0.0, .y = 0.0 });
    defer imgui.igPopStyleVar(1);

    const line_height = bold_font.*.LegacySize + imgui.igGetStyle().*.FramePadding.y * 2.0;
    const button_size = imgui.ImVec2{ .x = line_height, .y = line_height };

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.478, .y = 0.156, .z = 0.156, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.717, .y = 0.234, .z = 0.234, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.597, .y = 0.195, .z = 0.195, .w = 1.0 });

    imgui.igPushFont(bold_font, bold_font.*.LegacySize);
    if (imgui.igButton("X", button_size)) {
        vec.x = reset_value;
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    var values_x: f32 = vec.x;
    if (imgui.igDragFloat("##X", &values_x, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        vec.x = values_x;
    }
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.156, .y = 0.478, .z = 0.156, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.234, .y = 0.717, .z = 0.234, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.195, .y = 0.597, .z = 0.195, .w = 1.0 });

    imgui.igPushFont(bold_font, bold_font.*.LegacySize);
    if (imgui.igButton("Y", button_size)) {
        vec.*.y = reset_value;
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    var values_y: f32 = vec.y;
    if (imgui.igDragFloat("##Y", &values_y, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        vec.y = values_y;
    }
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.156, .y = 0.306, .z = 0.478, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.234, .y = 0.459, .z = 0.717, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.195, .y = 0.328, .z = 0.597, .w = 1.0 });

    imgui.igPushFont(bold_font, bold_font.*.LegacySize);
    if (imgui.igButton("Z", button_size)) {
        vec.*.z = reset_value;
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    var values_z: f32 = vec.z;
    if (imgui.igDragFloat("##Z", &values_z, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        vec.z = values_z;
    }
    imgui.igPopItemWidth();
}

pub fn RenderVec4(vec: *Vec4(f32), label: []const u8, reset_value: f32, speed: f32, column_width: f32) !void {
    const io = imgui.igGetIO_Nil();
    const bold_font = io.*.Fonts.*.Fonts.Data[0];
    imgui.igPushID_Str(label.ptr);
    defer imgui.igPopID();

    imgui.igColumns(2, 0, false);
    defer imgui.igColumns(1, 0, false);
    imgui.igSetColumnWidth(0, column_width);
    imgui.igText(label.ptr);
    imgui.igNextColumn();

    imgui.igPushMultiItemsWidths(4, imgui.igCalcItemWidth());
    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_ItemSpacing, .{ .x = 0.0, .y = 0.0 });
    defer imgui.igPopStyleVar(1);

    const line_height = bold_font.*.LegacySize + imgui.igGetStyle().*.FramePadding.y * 2.0;
    const button_size = imgui.ImVec2{ .x = line_height, .y = line_height };

    // X
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.478, .y = 0.156, .z = 0.156, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.717, .y = 0.234, .z = 0.234, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.597, .y = 0.195, .z = 0.195, .w = 1.0 });

    imgui.igPushFont(bold_font, bold_font.*.LegacySize);
    if (imgui.igButton("X", button_size)) {
        vec.x = reset_value;
    }
    imgui.igPopFont();
    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    var values_x: f32 = vec.x;
    if (imgui.igDragFloat("##X", &values_x, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        vec.x = values_x;
    }
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    // Y
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.156, .y = 0.478, .z = 0.156, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.234, .y = 0.717, .z = 0.234, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.195, .y = 0.597, .z = 0.195, .w = 1.0 });

    imgui.igPushFont(bold_font, bold_font.*.LegacySize);
    if (imgui.igButton("Y", button_size)) {
        vec.*.y = reset_value;
    }
    imgui.igPopFont();
    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    var values_y: f32 = vec.y;
    if (imgui.igDragFloat("##Y", &values_y, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        vec.y = values_y;
    }
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    // Z
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.156, .y = 0.306, .z = 0.478, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.234, .y = 0.459, .z = 0.717, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.195, .y = 0.328, .z = 0.597, .w = 1.0 });

    imgui.igPushFont(bold_font, bold_font.*.LegacySize);
    if (imgui.igButton("Z", button_size)) {
        vec.*.z = reset_value;
    }
    imgui.igPopFont();
    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    var values_z: f32 = vec.z;
    if (imgui.igDragFloat("##Z", &values_z, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        vec.z = values_z;
    }
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    // W
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.4, .y = 0.4, .z = 0.4, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.55, .y = 0.55, .z = 0.55, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.45, .y = 0.45, .z = 0.45, .w = 1.0 });

    imgui.igPushFont(bold_font, bold_font.*.LegacySize);
    if (imgui.igButton("W", button_size)) {
        vec.*.w = reset_value;
    }
    imgui.igPopFont();
    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    var values_w: f32 = vec.w;
    if (imgui.igDragFloat("##W", &values_w, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        vec.w = values_w;
    }
    imgui.igPopItemWidth();
}

//The euler triple the rotation fields show, kept in ImGui's per-window state storage so no
//editor-only data has to live on the component. `source` is the quaternion the triple was last
//written with; when it no longer matches, something else (a script, physics, a different entity
//under the same ID) changed the rotation and the triple is re-derived from it.
const QuatEulerCache = struct {
    const euler_keys = [3][*:0]const u8{ "##euler_x", "##euler_y", "##euler_z" };
    const source_keys = [4][*:0]const u8{ "##src_w", "##src_x", "##src_y", "##src_z" };

    fn Load(quat: Quat(f32)) Vec3(f32) {
        const storage = imgui.igGetStateStorage();
        //NaN default: a key that has never been written can never compare equal to a real quaternion
        const nan = std.math.nan(f32);
        const source = Quat(f32){
            .w = imgui.ImGuiStorage_GetFloat(storage, imgui.igGetID_Str(source_keys[0]), nan),
            .x = imgui.ImGuiStorage_GetFloat(storage, imgui.igGetID_Str(source_keys[1]), nan),
            .y = imgui.ImGuiStorage_GetFloat(storage, imgui.igGetID_Str(source_keys[2]), nan),
            .z = imgui.ImGuiStorage_GetFloat(storage, imgui.igGetID_Str(source_keys[3]), nan),
        };
        if (!std.meta.eql(source, quat)) return quat.ToDegrees();
        return .{
            .x = imgui.ImGuiStorage_GetFloat(storage, imgui.igGetID_Str(euler_keys[0]), 0.0),
            .y = imgui.ImGuiStorage_GetFloat(storage, imgui.igGetID_Str(euler_keys[1]), 0.0),
            .z = imgui.ImGuiStorage_GetFloat(storage, imgui.igGetID_Str(euler_keys[2]), 0.0),
        };
    }

    fn Store(euler: Vec3(f32), quat: Quat(f32)) void {
        const storage = imgui.igGetStateStorage();
        const euler_vals = [3]f32{ euler.x, euler.y, euler.z };
        const source_vals = [4]f32{ quat.w, quat.x, quat.y, quat.z };
        for (euler_keys, euler_vals) |key, val| imgui.ImGuiStorage_SetFloat(storage, imgui.igGetID_Str(key), val);
        for (source_keys, source_vals) |key, val| imgui.ImGuiStorage_SetFloat(storage, imgui.igGetID_Str(key), val);
    }
};

//reset_value and speed are both in degrees. Every edit writes the whole euler triple back through
//FromDegrees - editing one axis by rotating the quaternion by a delta cannot work here, the middle
//axis of an X-Y-Z decomposition is reachable by neither a pre- nor a post-multiply.
//
//The triple is not re-derived from the quaternion every frame: ToDegrees can only return a middle
//(Y) angle in [-90, 90], so re-deriving would turn a drag to Y = 91 into (180, 89, 180) on the next
//frame and the field could never pass 90. It lives in QuatEulerCache instead.
pub fn RenderQuat(quat: *Quat(f32), label: []const u8, reset_value: f32, speed: f32, column_width: f32) !void {
    const io = imgui.igGetIO_Nil();
    const bold_font = io.*.Fonts.*.Fonts.Data[0];
    imgui.igPushID_Str(label.ptr);
    defer imgui.igPopID();

    imgui.igColumns(2, 0, false);
    defer imgui.igColumns(1, 0, false);
    imgui.igSetColumnWidth(0, column_width);
    imgui.igText(label.ptr);
    imgui.igNextColumn();

    imgui.igPushMultiItemsWidths(3, imgui.igCalcItemWidth());
    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_ItemSpacing, .{ .x = 0.0, .y = 0.0 });
    defer imgui.igPopStyleVar(1);

    const line_height = bold_font.*.LegacySize + imgui.igGetStyle().*.FramePadding.y * 2.0;
    const button_size = imgui.ImVec2{ .x = line_height, .y = line_height };

    var euler = QuatEulerCache.Load(quat.*);
    defer QuatEulerCache.Store(euler, quat.*);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.478, .y = 0.156, .z = 0.156, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.717, .y = 0.234, .z = 0.234, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.597, .y = 0.195, .z = 0.195, .w = 1.0 });

    imgui.igPushFont(bold_font, bold_font.*.LegacySize);
    if (imgui.igButton("X", button_size)) {
        euler.x = reset_value;
        quat.* = .FromDegrees(euler);
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    if (imgui.igDragFloat("##X", &euler.x, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        quat.* = .FromDegrees(euler);
    }
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.156, .y = 0.478, .z = 0.156, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.234, .y = 0.717, .z = 0.234, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.195, .y = 0.597, .z = 0.195, .w = 1.0 });

    imgui.igPushFont(bold_font, bold_font.*.LegacySize);
    if (imgui.igButton("Y", button_size)) {
        euler.y = reset_value;
        quat.* = .FromDegrees(euler);
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);

    if (imgui.igDragFloat("##Y", &euler.y, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        quat.* = .FromDegrees(euler);
    }
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.156, .y = 0.306, .z = 0.478, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.234, .y = 0.459, .z = 0.717, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.195, .y = 0.328, .z = 0.597, .w = 1.0 });

    imgui.igPushFont(bold_font, bold_font.*.LegacySize);
    if (imgui.igButton("Z", button_size)) {
        euler.z = reset_value;
        quat.* = .FromDegrees(euler);
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    if (imgui.igDragFloat("##Z", &euler.z, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        quat.* = .FromDegrees(euler);
    }
    imgui.igPopItemWidth();
}

pub fn RenderStaticBitSet(comptime T: type, value: *T, label: []const u8) !void {
    imgui.igPushID_Str(label.ptr);
    defer imgui.igPopID();

    imgui.igText("%s", label.ptr);

    var i: usize = 0;
    while (i < T.bit_length) : (i += 1) {
        if (i != 0) imgui.igSameLine(0, -1);

        imgui.igPushID_Int(@intCast(i));
        defer imgui.igPopID();

        var on = value.isSet(i);
        var buf: [8]u8 = undefined;
        const id = std.fmt.bufPrintSentinel(&buf, "{d}", .{i}, 0) catch "?";
        if (imgui.igCheckbox(id.ptr, &on)) {
            if (on) value.set(i) else value.unset(i);
        }
    }
}

pub fn RenderUUID(uuid: *u64, label: [:0]const u8) !void {
    var buf: [32]u8 = undefined;
    var id_buf: [32]u8 = undefined;

    const formatted = try std.fmt.bufPrintSentinel(&buf, "{d}", .{uuid.*}, 0);
    const input_id = try std.fmt.bufPrintSentinel(&id_buf, "##{s}", .{formatted}, 0);

    imgui.igText("%s", label.ptr);
    imgui.igSameLine(0.0, 8.0);

    _ = imgui.igInputText(
        input_id.ptr,
        buf[0..].ptr,
        buf.len,
        imgui.ImGuiInputTextFlags_ReadOnly,
        null,
        null,
    );
}

pub fn RenderFloatInput(val: *f32, label: [:0]const u8, speed: f32, speed_fast: f32) !bool {
    return imgui.igInputFloat(label, val, speed, speed_fast, "%.3f", 0);
}

pub fn RenderFloatDrag(val: *f32, label: [:0]const u8, speed: f32, lower_bounds: f32, upper_bounds: f32) !bool {
    return imgui.igDragFloat(@ptrCast(label), val, speed, lower_bounds, upper_bounds, "%.3f", 0);
}

pub fn RenderFloat2Drag(val: *Vec2(f32), label: [:0]const u8, speed: f32, lower_bounds: f32, upper_bounds: f32) !void {
    _ = imgui.igDragFloat2(label, @ptrCast(val), speed, lower_bounds, upper_bounds, "%.3f", imgui.ImGuiSliderFlags_None);
}

pub fn RenderFloat4Drag(val: *Vec4(f32), label: [:0]const u8, speed: f32, lower_bounds: f32, upper_bounds: f32) !void {
    _ = imgui.igDragFloat4(label, @ptrCast(val), speed, lower_bounds, upper_bounds, "%.3f", imgui.ImGuiSliderFlags_None);
}

pub fn RenderColor4Edit(val: *Vec4(f32), label: [:0]const u8) !void {
    _ = imgui.igColorEdit4(label.ptr, @ptrCast(val), imgui.ImGuiColorEditFlags_None);
}

pub fn RenderIntInput(val: *u32, label: [:0]const u8, speed: f32, speed_fast: f32) !bool {
    return imgui.igInputInt(label, val, speed, speed_fast, 0);
}

pub fn RenderScalerInput(val: *u32, label: [:0]const u8, speed: u32, speed_fast: u32) !bool {
    return imgui.igInputScalar(label, imgui.ImGuiDataType_U32, val, speed, speed_fast, "%u", 0);
}

pub fn RenderFloat3Input(val: *Vec3(f32), label: [:0]const u8) !void {
    _ = imgui.igInputFloat3(label, @ptrCast(val), "%.3f", 0);
}

pub fn RenderEnum(comptime T: type, value: *T, label: [:0]const u8) !void {
    const field_names = std.meta.fieldNames(T);
    const current_index = @backingInt(value.*);

    var preview_buf: [32]u8 = undefined;
    const preview_cstr = std.fmt.bufPrintSentinel(&preview_buf, "{s}", .{@tagName(value.*)}, 0) catch unreachable;

    if (imgui.igBeginCombo(label.ptr, preview_cstr.ptr, 0)) {
        defer imgui.igEndCombo();

        for (field_names, 0..) |field_name, i| {
            const is_selected = (current_index == i);

            if (imgui.igSelectable_Bool(field_name, is_selected, 0, .{ .x = 0, .y = 0 })) {
                value.* = @fromBackingInt(@intCast(i));
            }
            if (is_selected) imgui.igSetItemDefaultFocus();
        }
    }
}

pub fn RenderUnion(comptime T: type, value: *T, label: [:0]const u8) !void {
    const field_names = @typeInfo(T).@"union".field_names;
    const field_types = @typeInfo(T).@"union".field_types;
    const current_index = @backingInt(@as(std.meta.Tag(T), value.*));

    var preview_buf: [32]u8 = undefined;
    const preview_cstr = try std.fmt.bufPrintSentinel(&preview_buf, "{s}", .{@tagName(value.*)}, 0);

    if (imgui.igBeginCombo(label.ptr, preview_cstr.ptr, 0)) {
        defer imgui.igEndCombo();

        inline for (field_names, 0..) |field_name, i| {
            const is_selected = (current_index == i);

            if (imgui.igSelectable_Bool(field_name, is_selected, 0, .{ .x = 0, .y = 0 })) {
                value.* = @unionInit(T, field_name, defaultOf(field_types[i]));
            }
            if (is_selected) imgui.igSetItemDefaultFocus();
        }
    }

    try value.ImguiRender();
}

fn defaultOf(comptime PayloadT: type) PayloadT {
    if (@typeInfo(PayloadT) == .@"struct" and @hasField(PayloadT, "default")) return .default;
    return std.mem.zeroes(PayloadT);
}

pub fn RenderBool(value: *bool, label: [:0]const u8) !void {
    _ = imgui.igCheckbox(@ptrCast(label), value);
}

pub fn ImguiSeparator() !void {
    imgui.igSeparator();
}

pub fn RenderUVCoords(open: *bool, uv0: *Vec2(f32), uv1: *Vec2(f32), engine_context: *EngineContext, texture_asset: *Texture2D) !void {
    if (!open.*) return;

    imgui.igSetNextWindowSize(.{ .x = @floatFromInt(texture_asset.GetWidth()), .y = @floatFromInt(texture_asset.GetHeight()) }, imgui.ImGuiCond_Once);

    //igEnd has to pair with every igBegin, even when Begin returns false because the window is collapsed
    defer imgui.igEnd();
    if (imgui.igBegin("Texture Coordinate Editor", open, 0)) {
        const available = imgui.igGetContentRegionAvail();
        const tex_w: f32 = @floatFromInt(texture_asset.GetWidth());
        const tex_h: f32 = @floatFromInt(texture_asset.GetHeight());
        const texture_aspect = if (tex_h > 0) tex_w / tex_h else 1.0;

        const frame_h = imgui.igGetFrameHeightWithSpacing();
        const text_h = imgui.igGetTextLineHeightWithSpacing();
        const reserved_controls_h: f32 = text_h + frame_h * 2 + 8.0;
        const allowed_h = @max(available.y - reserved_controls_h, 50.0);

        var draw_w = available.x;
        var draw_h = draw_w / texture_aspect;
        if (draw_h > allowed_h) {
            draw_h = allowed_h;
            draw_w = draw_h * texture_aspect;
        }

        imgui.igImage(
            try engine_context.mImguiManager.GetImguiTexture(engine_context, texture_asset),
            .{ .x = draw_w, .y = draw_h },
            .{ .x = uv0.x, .y = 1.0 - uv0.y },
            .{ .x = uv1.x, .y = 1.0 - uv1.y },
        );

        imgui.igDummy(.{ .x = 0.0, .y = 8.0 });
        imgui.igSeparatorText("Texture Coordinates (UV)");

        _ = imgui.igSliderFloat2("UV0 (Min)", @ptrCast(uv0), 0.0, 1.0, "%.3f", imgui.ImGuiSliderFlags_AlwaysClamp);
        _ = imgui.igSliderFloat2("UV1 (Max)", @ptrCast(uv1), 0.0, 1.0, "%.3f", imgui.ImGuiSliderFlags_AlwaysClamp);

        uv1.x = @max(uv1.x, uv0.x);
        uv1.y = @max(uv1.y, uv0.y);

        if (imgui.igIsMouseDoubleClicked_Nil(0) and imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None)) {
            open.* = false;
        }
    }
}

pub fn RenderTexture2D(engine_context: *EngineContext, texture_handle: *AssetHandle, texture_asset: *Texture2D, edit_flag: *bool) !void {
    imgui.igImage(
        try engine_context.mImguiManager.GetImguiTexture(engine_context, texture_asset),
        .{ .x = 50.0, .y = 50.0 },
        .{ .x = 0.0, .y = 0.0 },
        .{ .x = 1.0, .y = 1.0 },
    );

    if (imgui.igIsItemHovered(imgui.ImGuiHoveredFlags_None) and imgui.igIsMouseDoubleClicked_Nil(0)) {
        edit_flag.* = true;
    }

    if (imgui.igBeginDragDropTarget()) {
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload("Texture2DAsset", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            texture_handle.ReleaseAsset();
            texture_handle.* = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = path, .path_type = .Prj } });
        }
    }
}

pub fn RenderAssetRef(engine_context: *EngineContext, asset_handle: *AssetHandle, label: []const u8, drag_drop_payload_id: [:0]const u8) !void {
    const frame_allocator = engine_context.FrameAllocator();
    if (asset_handle.mID != AssetHandle.NullObject) {
        const file_data_asset = asset_handle.GetFileMetaData();
        const name = std.fs.path.stem(std.fs.path.basename(file_data_asset.mRelPath.items));
        const name_term = try frame_allocator.dupeSentinel(u8, name, 0);
        imgui.igTextUnformatted(label.ptr, null);
        imgui.igSameLine(0.0, 0.0);
        imgui.igTextUnformatted(name_term, null);
    } else {
        imgui.igTextUnformatted(label.ptr, null);
        imgui.igSameLine(0.0, 0.0);
        imgui.igTextUnformatted("None", null);
    }

    if (imgui.igBeginDragDropTarget()) {
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload(drag_drop_payload_id.ptr, imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            asset_handle.ReleaseAsset();
            asset_handle.* = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = path, .path_type = .Prj } });
        }
    }
}

/// Shows the name of the entity a component references (or None) and acts as a drop target for
/// entities dragged out of the ECS display. It does not write the ref itself: the new entity is
/// returned so the caller can go through whatever setter keeps both sides linked. Clearing from the
/// right click menu returns .uninit. Returns null when nothing changed this frame.
pub fn RenderEntityRef(engine_context: *EngineContext, entity_ref: *const Entity, label: [:0]const u8) !?Entity {
    const frame_allocator = engine_context.FrameAllocator();
    var new_entity: ?Entity = null;

    imgui.igPushID_Str(label.ptr);
    defer imgui.igPopID();

    imgui.igTextUnformatted(label.ptr, null);
    imgui.igSameLine(0.0, 8.0);

    if (entity_ref.IsActive()) {
        //GetName assumes a NameComponent, fall back to the ID for entities without one
        const name = if (entity_ref.HasComponent(NameComponent))
            try std.fmt.allocPrintSentinel(frame_allocator, "{s}", .{entity_ref.GetName()}, 0)
        else
            try std.fmt.allocPrintSentinel(frame_allocator, "Entity {d}", .{entity_ref.mID}, 0);
        imgui.igTextUnformatted(name.ptr, null);
    } else {
        imgui.igTextUnformatted("None", null);
    }

    if (imgui.igBeginPopupContextItem("EntityRefContext", imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();
        if (imgui.igMenuItem_Bool("Clear", "", false, entity_ref.IsActive())) {
            new_entity = .uninit;
        }
    }

    if (imgui.igBeginDragDropTarget()) {
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload(ENTITY_REF_PAYLOAD, imgui.ImGuiDragDropFlags_None)) |payload| {
            new_entity = @as(*const Entity, @ptrCast(@alignCast(payload.*.Data))).*;
        }
    }

    return new_entity;
}

const InputTextContext = struct {
    array: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
};

pub fn RenderTextInput(engine_context: *EngineContext, array: *std.ArrayList(u8), label: []const u8) !void {
    const frame_allocator = engine_context.FrameAllocator();
    const engine_allocator = engine_context.EngineAllocator();

    const text = try frame_allocator.dupeSentinel(u8, array.items, 0);
    var ctx = InputTextContext{ .array = array, .allocator = engine_allocator };
    if (imgui.igInputText(label.ptr, text.ptr, text.len + 1, imgui.ImGuiInputTextFlags_CallbackResize, InputTextCallback, @ptrCast(&ctx))) {
        _ = array.swapRemove(array.items.len - 1);
    }
}

pub fn RenderText(text: [:0]const u8) !void {
    imgui.igTextUnformatted(text.ptr, text.ptr + text.len);
}

fn InputTextCallback(data: [*c]imgui.ImGuiInputTextCallbackData) callconv(.c) c_int {
    if (data.*.EventFlag == imgui.ImGuiInputTextFlags_CallbackResize) {
        const ctx: *InputTextContext = @ptrCast(@alignCast(data.*.UserData.?));
        _ = ctx.array.resize(ctx.allocator, @intCast(data.*.BufTextLen + 1)) catch return 0;
        data.*.Buf = ctx.array.items.ptr;
    }
    return 0;
}

fn SetDarkThemeColors(style: *imgui.struct_ImGuiStyle) void {

    //background
    style.*.Colors[imgui.ImGuiCol_WindowBg] = .{ .x = 2.0 / 255.0, .y = 5.0 / 255.0, .z = 8.0 / 255.0, .w = 1.0 };

    //Headers
    style.*.Colors[imgui.ImGuiCol_Header] = .{ .x = 155 / 255, .y = 207 / 255, .z = 234 / 255, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_HeaderHovered] = .{ .x = 0.293, .y = 0.317, .z = 0.382, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_HeaderActive] = .{ .x = 0.235, .y = 0.254, .z = 0.306, .w = 1.0 };

    //Buttons
    style.*.Colors[imgui.ImGuiCol_Button] = .{ .x = 0.250, .y = 0.266, .z = 0.358, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_ButtonHovered] = .{ .x = 0.375, .y = 0.399, .z = 0.537, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_ButtonActive] = .{ .x = 0.312, .y = 0.322, .z = 0.447, .w = 1.0 };

    //Frame BG
    style.*.Colors[imgui.ImGuiCol_FrameBg] = .{ .x = 0.317, .y = 0.290, .z = 0.290, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_FrameBgHovered] = .{ .x = 0.475, .y = 0.435, .z = 0.435, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_FrameBgActive] = .{ .x = 0.396, .y = 0.362, .z = 0.362, .w = 1.0 };
    //tabs
    style.*.Colors[imgui.ImGuiCol_Tab] = .{ .x = 255 / 255, .y = 207 / 255, .z = 234 / 255, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_TabHovered] = .{ .x = 155 / 255, .y = 207 / 255, .z = 234 / 255, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_TabSelected] = .{ .x = 0.375, .y = 0.210, .z = 0.493, .w = 1.0 };

    //titles
    style.*.Colors[imgui.ImGuiCol_TitleBg] = .{ .x = 198.0 / 255.0, .y = 113.0 / 255.0, .z = 186.0 / 255.0, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_TitleBgActive] = .{ .x = 0.188, .y = 0.104, .z = 0.246, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_TitleBgCollapsed] = .{ .x = 0.8, .y = 0.3, .z = 0.3, .w = 1.0 };

    //resize
    style.*.Colors[imgui.ImGuiCol_ResizeGrip] = .{ .x = 0.8, .y = 0.3, .z = 0.3, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_ResizeGripHovered] = .{ .x = 0.303, .y = 0.333, .z = 0.340, .w = 1.0 };
    style.*.Colors[imgui.ImGuiCol_ResizeGripActive] = .{ .x = 0.404, .y = 0.444, .z = 0.454, .w = 1.0 };
}

fn getOrCreatePreviewTexture(self: *ImguiManager, engine_allocator: std.mem.Allocator, device: *sdl.SDL_GPUDevice) !*sdl.SDL_GPUTexture {
    if (self.mNumUsedTextures >= self.mImguiTextures.items.len) {
        //have to make a new one
        const info = sdl.SDL_GPUTextureCreateInfo{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
            .width = TEXTURE_SIZE,
            .height = TEXTURE_SIZE,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
            .props = 0,
        };

        const new_texture = sdl.SDL_CreateGPUTexture(device, &info) orelse return error.TextureCreateFail;

        try self.mImguiTextures.append(engine_allocator, new_texture);
        self.mNumUsedTextures += 1;

        return new_texture;
    } else {
        const texture = self.mImguiTextures.items[self.mNumUsedTextures];
        self.mNumUsedTextures += 1;
        return texture;
    }
}
