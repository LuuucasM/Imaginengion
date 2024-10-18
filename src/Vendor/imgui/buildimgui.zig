const std = @import("std");
const Compile = std.Build.Step.Compile;

pub fn Add(exe: *Compile) void {
    const options = std.Build.Module.AddCSourceFilesOptions{
        .files = &[_][]const u8{
            "src/Vendor/imgui/imgui/backends/imgui_impl_glfw.cpp",
            "src/Vendor/imgui/imgui/backends/imgui_impl_opengl3.cpp",
        },
        .flags = &[_][]const u8{
            "-D_CRT_SECURE_NO_WARNINGS",
            "-lstdc++",
            "-D_IMGUI_IMPL_OPENGL_LOADER_GL3W",
        },
    };
    exe.addCSourceFiles(options);
    exe.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    exe.addIncludePath(.{ .path = "src/Vendor/imgui/" });
    exe.addIncludePath(.{ .path = "src/Vendor/imgui/generator/output/" });
    exe.addIncludePath(.{ .path = "src/Vendor/imgui/imgui/" });
    exe.addLibraryPath(.{ .path = "src/Vendor/imgui/zig-out/lib/" });
    exe.linkSystemLibrary("imgui");
}
