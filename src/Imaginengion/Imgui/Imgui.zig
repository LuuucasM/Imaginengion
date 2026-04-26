const std = @import("std");
const Application = @import("../Core/Application.zig");
const Window = @import("../Windows/Window.zig");
const imgui = @import("../Core/CImports.zig").imgui;
const sdl = @import("../Core/CImports.zig").sdl;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Texture2D = @import("../Assets/Assets.zig").Texture2D;
const ImguiManager = @This();

const TEXTURE_SIZE: usize = 128;

mImguiTextures: std.ArrayList(*sdl.SDL_GPUTexture) = .empty,
mImguiTexturesSize: usize = 0,

pub fn Init(_: ImguiManager, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("Imgui::Init", @src());
    defer zone.Deinit();
    _ = imgui.igCreateContext(null);
    const io: *imgui.ImGuiIO = imgui.igGetIO();
    io.ConfigFlags |= imgui.ImGuiConfigFlags_NavEnableKeyboard; // Enable Keyboard Controls
    io.ConfigFlags |= imgui.ImGuiConfigFlags_NavEnableGamepad; // Enable Gamepad Controls
    io.ConfigFlags |= imgui.ImGuiConfigFlags_DockingEnable; // Enable Docking
    io.ConfigFlags |= imgui.ImGuiConfigFlags_ViewportsEnable; // Enable Multi-Viewport / Platform Windows

    const style = imgui.igGetStyle();

    imgui.igStyleColorsDark(style);
    //imgui.igStyleColorsLight(style);

    // When viewports are enabled we tweak WindowRounding/WindowBg so platform windows can look identical to regular ones.
    if (io.ConfigFlags & imgui.ImGuiConfigFlags_ViewportsEnable) {
        style.WindowRounding = 0.0;
        style.Colors[imgui.ImGuiCol_WindowBg].w = 1.0;
    }

    SetDarkThemeColors(style);

    _ = imgui.ImGui_ImplSDL3_InitForSDLGPU(engine_context.mAppWindow.GetNativeWindow());
    const device: ?*sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());
    const init_info: imgui.ImGui_ImplSDLGPU3_InitInfo = .{
        .Device = device,
        .ColorTargetFormat = sdl.SDL_GetGPUSwapchainTextureFormat(device, engine_context.mAppWindow.GetNativeWindow()),
        .MSAASamples = sdl.SDL_GPU_SAMPLECOUNT_1,
        .SwapchainComposition = sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
        .PresentMode = sdl.SDL_GPU_PRESENTMODE_VSYNC,
    };
    _ = imgui.ImGui_ImplSDLGPU3_Init(&init_info);
}
pub fn Deinit(self: ImguiManager, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("Imgui::Deinit", @src());
    defer zone.Deinit();

    const device: ?*sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());

    sdl.SDL_WaitForGPUIdle(device);
    imgui.ImGui_ImplSDLGPU3_Shutdown();
    imgui.ImGui_ImplSDL3_Shutdown();
    imgui.igDestroyContext(null);

    self.mImguiTextures.deinit(engine_context);
}
pub fn Begin(self: ImguiManager) void {
    const zone = Tracy.ZoneInit("Imgui Begin", @src());
    defer zone.Deinit();
    imgui.ImGui_ImplSDLGPU3_NewFrame();
    imgui.ImGui_ImplSDL3_NewFrame();
    imgui.igNewFrame();
    self.mImguiTexturesSize = 0;
}
pub fn End(_: ImguiManager, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("ImguiEnd ", @src());
    defer zone.Deinit();

    const io: *imgui.ImGuiIO = imgui.igGetIO();
    io.DisplaySize = .{
        .x = @floatFromInt(engine_context.mAppWindow.GetWidth()),
        .y = @floatFromInt(engine_context.mAppWindow.GetHeight()),
    };

    imgui.igRender();

    const cmd_buffer: *sdl.SDL_GPUCommandBuffer = @ptrCast(engine_context.mRenderer.mPlatform.GetCommandBuff());

    const draw_data = imgui.igGetDrawData();
    imgui.ImGui_ImplSDLGPU3_RenderDrawData(draw_data, cmd_buffer);

    if (io.ConfigFlags & imgui.ImGuiConfigFlags_ViewportsEnable != 0) {
        imgui.igUpdatePlatformWindows();
        imgui.igRenderPlatformWindowsDefault(null, null);
    }
}
pub fn GetImguiTexture(self: ImguiManager, engine_context: *EngineContext, texture: Texture2D) !*sdl.SDL_GPUTexture {
    const device: *sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());

    const preview = try self.getOrCreatePreviewTexture(device);

    const offset_x, const offset_y = engine_context.mRenderer.mTextureManager.GetPixelOffsets(texture.GetTextureHandle());
    const layer = engine_context.mRenderer.mTextureManager.GetLayerIndex(texture.GetTextureHandle());

    const copy_w = @min(texture.GetWidth(), TEXTURE_SIZE);
    const copy_h = @min(texture.GetHeight(), TEXTURE_SIZE);

    const dst_x = (TEXTURE_SIZE - copy_w) / 2;
    const dst_y = (TEXTURE_SIZE - copy_h) / 2;

    const cmd = sdl.SDL_AcquireGPUCommandBuffer(engine_context.gpu_device) orelse error.AquireGPUCMDFailed;
    defer sdl.SDL_SubmitGPUCommandBuffer(cmd);

    const copy_pass = sdl.SDL_BeginGPUCopyPass(cmd);
    defer sdl.SDL_EndGPUCopyPass(copy_pass);

    const atlas_texture: *sdl.SDL_GPUTexture = @ptrCast(texture.GetTexture());

    const src = sdl.SDL_GPUTextureLocation{
        .texture = atlas_texture,
        .mip_level = 0,
        .layer = layer,
        .x = offset_x,
        .y = offset_y,
        .z = 0,
    };

    const dst = sdl.SDL_GPUTextureLocation{
        .texture = preview,
        .mip_level = 0,
        .layer = 0,
        .x = dst_x,
        .y = dst_y,
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

    return preview;
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

fn getOrCreatePreviewTexture(self: *ImguiManager, device: *sdl.SDL_GPUDevice) !*sdl.SDL_GPUTexture {
    if (self.mImguiTextureIndex >= self.mImguiTextures.items.len) {
        //have to make a new one
        const info = sdl.SDL_GPUTextureCreateInfo{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
            .width = 256,
            .height = 256,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
            .props = 0,
        };
        return sdl.SDL_CreateGPUTexture(device, &info) orelse error.TextureCreateFail;
    } else {
        const texture = self.mImguiTextures.items[self.mImguiTexturesSize];
        self.mImguiTexturesSize += 1;
        return texture;
    }
}
