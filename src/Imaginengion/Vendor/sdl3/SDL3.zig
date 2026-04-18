pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_video.h");
    @cInclude("SDL3/SDL_events.h");
    @cInclude("SDL3/SDL_gpu.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

pub const vk = @cImport({
    @cDefine("VK_NO_PROTOTYPES", "1");
    @cInclude("vulkan/vulkan.h");
});
