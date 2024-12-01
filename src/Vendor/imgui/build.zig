const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{ .name = "imgui", .target = target, .optimize = optimize });
    lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "./" } });
    lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "imgui/" } });
    const options = std.Build.Module.AddCSourceFilesOptions{
        .files = &[_][]const u8{
            "imgui/imgui.cpp",
            "imgui/imgui_demo.cpp",
            "imgui/imgui_draw.cpp",
            "imgui/imgui_tables.cpp",
            "imgui/imgui_widgets.cpp",
            "cimgui.cpp",
        },
        .flags = &[_][]const u8{
            "-D_CRT_SECURE_NO_WARNINGS",
            "-lstdc++",
            "-D_IMGUI_IMPL_OPENGL_LOADER_GL3W",
        },
    };
    lib.addCSourceFiles(options);

    lib.linkSystemLibrary("c");
    lib.linkSystemLibrary("c++");

    //---------------GLFW-----------
    lib.addLibraryPath(.{ .src_path = .{ .owner = b, .sub_path = "../GLFW/zig-out/lib/" } });
    lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "../GLFW/include/" } });
    lib.linkSystemLibrary("GLFW");

    b.installArtifact(lib);
}
