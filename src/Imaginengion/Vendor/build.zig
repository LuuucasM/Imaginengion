const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const imgui_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    const imgui_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "Imgui",
        .root_module = imgui_mod,
    });

    imgui_mod.addIncludePath(b.path("imgui/"));
    imgui_mod.addIncludePath(b.path("imgui/imgui/"));
    imgui_mod.addIncludePath(b.path("sdl3/include/"));

    const options = std.Build.Module.AddCSourceFilesOptions{
        .files = &[_][]const u8{
            "imgui/imgui/imgui.cpp",
            "imgui/imgui/imgui_demo.cpp",
            "imgui/imgui/imgui_draw.cpp",
            "imgui/imgui/imgui_tables.cpp",
            "imgui/imgui/imgui_widgets.cpp",

            "imgui/imgui/backends/imgui_impl_sdl3.cpp",
            "imgui/imgui/backends/imgui_impl_sdlgpu3.cpp",

            "imgui/cimgui.cpp",
        },
        .flags = &[_][]const u8{
            "-D_CRT_SECURE_NO_WARNINGS",
            "-DCIMGUI_USE_SDL3",
            "-DCIMGUI_USE_SDLGPU",
        },
    };
    imgui_mod.addCSourceFiles(options);

    if (target.result.os.tag == .windows) {
        imgui_mod.linkSystemLibrary("gdi32", .{ .needed = true });
    }

    b.installArtifact(imgui_lib);
}
