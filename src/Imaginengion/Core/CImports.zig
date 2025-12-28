pub const glad = @import("GLAD").c;

pub const glfw = @import("GLFW").c;

pub const imgui = @import("IMGUI").c;

pub const stb = @cImport({
    @cInclude("stb_image.h");
});

pub const nfd = @import("NFD").c;

const build_options = @import("build_options");
pub const enable_tracy = build_options.enable_tracy;
pub const tracy = if (enable_tracy) @import("Tracy").c else void;

pub const miniaudio = @import("MiniAudio").c;
