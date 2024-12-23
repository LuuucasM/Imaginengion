const std = @import("std");
const Compile = std.Build.Step.Compile;

pub fn Add(exe: *Compile, b: *std.Build) void {
    const options = std.Build.Module.AddCSourceFilesOptions{
        .files = &[_][]const u8{
            "src/Vendor/imgui/imgui/backends/imgui_impl_glfw.cpp",
            "src/Vendor/imgui/imgui/backends/imgui_impl_opengl3.cpp",
        },
        .flags = &[_][]const u8{
            "-fno-exceptions",
            "-fno-rtti",
            "-D_CRT_SECURE_NO_WARNINGS",
            "-DIMGUI_IMPL_API=extern\"C\"",
            "-DIMGUI_IMPL_OPENGL_LOADER_CUSTOM",
        },
    };
    exe.addCSourceFiles(options);

    exe.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/imgui/" } });
    exe.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/imgui/generator/output/" } });
    exe.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/imgui/imgui/" } });
    exe.addLibraryPath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/imgui/zig-out/lib/" } });
    exe.linkSystemLibrary("imgui");
}
