#pragma once

#include <stdint.h>
#include <stdbool.h>

typedef struct SDL_GPUDevice SDL_GPUDevice;
typedef struct SDL_GPUCommandBuffer SDL_GPUCommandBuffer;
typedef struct SDL_GPURenderPass SDL_GPURenderPass;
typedef struct SDL_GPUGraphicsPipeline SDL_GPUGraphicsPipeline;

typedef uint32_t SDL_GPUTextureFormat;
typedef uint32_t SDL_GPUSwapchainComposition;
typedef uint32_t SDL_GPUPresentMode;
typedef uint32_t SDL_GPUSampleCount;
typedef struct ImDrawData ImDrawData;

typedef struct ImGui_ImplSDLGPU3_InitInfo {
    SDL_GPUDevice* Device;
    SDL_GPUTextureFormat ColorTargetFormat;
    SDL_GPUSampleCount MSAASamples;
    SDL_GPUSwapchainComposition SwapchainComposition;
    SDL_GPUPresentMode PresentMode;
} ImGui_ImplSDLGPU3_InitInfo;

#ifdef __cplusplus
extern "C" {
#endif

bool ImGui_ImplSDLGPU3_Init(ImGui_ImplSDLGPU3_InitInfo* info);
void ImGui_ImplSDLGPU3_Shutdown();
void ImGui_ImplSDLGPU3_NewFrame();
void ImGui_ImplSDLGPU3_PrepareDrawData(ImDrawData* draw_data, SDL_GPUCommandBuffer* command_buffer);
void ImGui_ImplSDLGPU3_RenderDrawData(ImDrawData* draw_data, SDL_GPUCommandBuffer* command_buffer, SDL_GPURenderPass* render_pass, SDL_GPUGraphicsPipeline* pipeline);

#ifdef __cplusplus
}
#endif