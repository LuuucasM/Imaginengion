const builtin = @import("builtin");
pub const glad = @import("GLAD").c;
pub const glfw = @import("GLFW").c;

pub const imgui = @import("IMGUI").c;
pub const stb = @cImport({
    @cInclude("stb_image.h");
});

pub const nfd = @import("NFD").c;

pub const tracy = @import("Tracy").c;
