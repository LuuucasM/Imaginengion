const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{ .name = "GLFW", .target = target, .optimize = optimize });
    lib.addIncludePath(.{ .path = "include/" });
    const options = switch (builtin.os.tag) {
        .windows => blk: {
            lib.linkSystemLibrary("gdi32");
            break :blk std.Build.Module.AddCSourceFilesOptions{
                .files = &[_][]const u8{
                    "src/context.c",
                    "src/init.c",
                    "src/input.c",
                    "src/monitor.c",
                    "src/vulkan.c",
                    "src/window.c",
                    "src/platform.c",
                    "src/null_init.c",
                    "src/null_monitor.c",
                    "src/null_window.c",
                    "src/null_joystick.c",
                    "src/win32_init.c",
                    "src/win32_joystick.c",
                    "src/win32_monitor.c",
                    "src/win32_time.c",
                    "src/win32_thread.c",
                    "src/win32_window.c",
                    "src/wgl_context.c",
                    "src/egl_context.c",
                    "src/osmesa_context.c",
                    "src/win32_module.c",
                },
                .flags = &[_][]const u8{
                    "-D_GLFW_WIN32",
                    "-D_CRT_SECURE_NO_WARNINGS",
                },
            };
        },
        .linux => blk: {
            break :blk std.Build.Module.AddCSourceFilesOptions{
                .files = &[_][]const u8{
                    "src/context.c",
                    "src/init.c",
                    "src/input.c",
                    "src/monitor.c",
                    "src/vulkan.c",
                    "src/window.c",
                    "src/platform.c",
                    "src/null_init.c",
                    "src/null_monitor.c",
                    "src/null_window.c",
                    "src/null_joystick.c",
                    "src/x11_init.c",
                    "src/x11_monitor.c",
                    "src/xx1_window.c",
                    "src/xkb_unicode.c",
                    "src/posix_time.c",
                    "src/posix_thread.c",
                    "src/glx_context.c",
                    "src/egl_context.c",
                    "src/osmesa_context.c",
                    "src/linux_joystick.c",
                },
                .flags = &[_][]const u8{
                    "-D_GLFW_X11",
                    "-D_CRT_SECURE_NO_WARNINGS",
                },
            };
        },
        else => @compileError("Do not support the OS given !\n"),
    };
    lib.addCSourceFiles(options);
    lib.linkSystemLibrary("c");
    b.installArtifact(lib);
}
