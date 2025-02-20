const std = @import("std");
const builtin = @import("builtin");
const buildglfw = @import("src/Vendor/GLFW/buildglfw.zig");
const buildglad = @import("src/Vendor/Glad/buildglad.zig");
const buildimgui = @import("src/Vendor/imgui/buildimgui.zig");
const buildstb = @import("src/Vendor/stb/buildstb.zig");
const buildnativefiledialog = @import("src/Vendor/nativefiledialog/buildnativefiledialog.zig");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //-----------GLFW--------------
    const glfw_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "GLFW",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = null,
        }),
    });
    glfw_lib.addIncludePath(.{ .src_path = "src/Vendor/GLFW/include/" });
    {
        const options = switch (builtin.os.tag) {
            .windows => blk: {
                glfw_lib.linkSystemLibrary("gdi32");
                break :blk std.Build.Module.AddCSourceFilesOptions{
                    .files = &[_][]const u8{
                        "src/Vendor/GLFW/src/context.c",
                        "src/Vendor/GLFW/src/init.c",
                        "src/Vendor/GLFW/src/input.c",
                        "src/Vendor/GLFW/src/monitor.c",
                        "src/Vendor/GLFW/src/vulkan.c",
                        "src/Vendor/GLFW/src/window.c",
                        "src/Vendor/GLFW/src/platform.c",
                        "src/Vendor/GLFW/src/null_init.c",
                        "src/Vendor/GLFW/src/null_monitor.c",
                        "src/Vendor/GLFW/src/null_window.c",
                        "src/Vendor/GLFW/src/null_joystick.c",
                        "src/Vendor/GLFW/src/win32_init.c",
                        "src/Vendor/GLFW/src/win32_joystick.c",
                        "src/Vendor/GLFW/src/win32_monitor.c",
                        "src/Vendor/GLFW/src/win32_time.c",
                        "src/Vendor/GLFW/src/win32_thread.c",
                        "src/Vendor/GLFW/src/win32_window.c",
                        "src/Vendor/GLFW/src/wgl_context.c",
                        "src/Vendor/GLFW/src/egl_context.c",
                        "src/Vendor/GLFW/src/osmesa_context.c",
                        "src/Vendor/GLFW/src/win32_module.c",
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
                        "src/Vendor/GLFW/src/context.c",
                        "src/Vendor/GLFW/src/init.c",
                        "src/Vendor/GLFW/src/input.c",
                        "src/Vendor/GLFW/src/monitor.c",
                        "src/Vendor/GLFW/src/vulkan.c",
                        "src/Vendor/GLFW/src/window.c",
                        "src/Vendor/GLFW/src/platform.c",
                        "src/Vendor/GLFW/src/null_init.c",
                        "src/Vendor/GLFW/src/null_monitor.c",
                        "src/Vendor/GLFW/src/null_window.c",
                        "src/Vendor/GLFW/src/null_joystick.c",
                        "src/Vendor/GLFW/src/x11_init.c",
                        "src/Vendor/GLFW/src/x11_monitor.c",
                        "src/Vendor/GLFW/src/xx1_window.c",
                        "src/Vendor/GLFW/src/xkb_unicode.c",
                        "src/Vendor/GLFW/src/posix_time.c",
                        "src/Vendor/GLFW/src/posix_thread.c",
                        "src/Vendor/GLFW/src/glx_context.c",
                        "src/Vendor/GLFW/src/egl_context.c",
                        "src/Vendor/GLFW/src/osmesa_context.c",
                        "src/Vendor/GLFW/src/linux_joystick.c",
                    },
                    .flags = &[_][]const u8{
                        "-D_GLFW_X11",
                        "-D_CRT_SECURE_NO_WARNINGS",
                    },
                };
            },
            else => @compileError("Do not support the OS given !\n"),
        };
        glfw_lib.addCSourceFiles(options);
    }
    //------------END GLFW---------------
    //-----------GLAD--------------
    const glad_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "GLAD",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    glad_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/Glad/include/" } });
    {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/Vendor/Glad/src/glad.c",
            },
        };
        glad_lib.addCSourceFiles(options);
    }
    //-----------IMGUI--------------
    const imgui_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "IMGUI",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .root_source_file = null,
        }),
    });
    {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/Vendor/imgui/imgui/imgui.cpp",
                "src/Vendor/imgui/imgui/imgui_demo.cpp",
                "src/Vendor/imgui/imgui/imgui_draw.cpp",
                "src/Vendor/imgui/imgui/imgui_tables.cpp",
                "src/Vendor/imgui/imgui/imgui_widgets.cpp",
                "src/Vendor/imgui/ImGuizmo/ImGuizmo.cpp",
                "src/Vendor/imgui/cimgui.cpp",
                "src/Vendor/imgui/cimguizmo.cpp",
            },
            .flags = &[_][]const u8{
                "-D_CRT_SECURE_NO_WARNINGS",
                "-lstdc++",
                "-D_IMGUI_IMPL_OPENGL_LOADER_GL3W",
            },
        };
        imgui_lib.addCSourceFiles(options);
    }
    imgui_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/imgui/" } });
    imgui_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/imgui/imgui/" } });
    imgui_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/GLFW/include/" } });
    imgui_lib.linkLibrary(glfw_lib);
    //TODO: might have to add glfw as a module to imgui_lib for imgui to be able to access the glfw stuff? if not remove this
    //-----------NFD--------------
    const nfd_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "NFD",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });
    {
        const options = switch (builtin.os.tag) {
            .windows => blk: {
                break :blk std.Build.Module.AddCSourceFilesOptions{
                    .files = &[_][]const u8{
                        "src/Vendor/nativefiledialog/src/nfd_common.c",
                        "src/Vendor/nativefiledialog/src/nfd_win.cpp",
                    },
                };
            },
            .linux => blk: {
                break :blk std.Build.Module.AddCSourceFilesOptions{
                    .files = &[_][]const u8{
                        "src/Vendor/nativefiledialog/src/nfd_common.c",
                        "src/Vendor/nativefiledialog/src/nfd_gtk.c",
                    },
                };
            },
            .macos => blk: {
                break :blk std.Build.Module.AddCSourceFilesOptions{
                    .files = &[_][]const u8{
                        "src/Vendor/nativefiledialog/src/nfd_common.c",
                        "src/Vendor/nativefiledialog/src/nfd_cocoa.m",
                    },
                };
            },
            else => @compileError("Do not support the OS given !\n"),
        };
        nfd_lib.addCSourceFiles(options);
    }

    nfd_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/nativefiledialog/src/include/" } });
    //-----------IMAGINENGION EDITOR---------------
    const engine_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "Imaginengion",
        .root_module = b.createModule(
            .{
                .optimize = optimize,
                .target = target,
                .link_libc = true,
                .link_libcpp = true,
                .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion.zig" } },
            },
        ),
    });

    //-----------STB--------------
    {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/Vendor/stb/stb.c",
            },
            .flags = &[_][]const u8{
                "-std=c99",
            },
        };
        engine_lib.addCSourceFiles(options);
        engine_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/stb/" } });
    }

    if (builtin.os.tag == .windows) {
        glfw_lib.linkSystemLibrary("gdi32");
        imgui_lib.linkSystemLibrary("gdi32");

        nfd_lib.linkSystemLibrary("comdlg32");
        nfd_lib.linkSystemLibrary("ole32");
    }

    //TODO: convert these from their own files into this file
    //buildglfw.Add(exe, b);
    //buildglad.Add(exe, b);
    //buildimgui.Add(exe, b);
    //buildstb.Add(exe, b);
    //buildnativefiledialog.Add(exe, b);

    b.installArtifact(engine_lib);

    //TODO: define an exe which links and depends on the engine_lib
    //const run_cmd = b.addRunArtifact(exe);
    //run_cmd.step.dependOn(b.getInstallStep());
    //
    //// This allows the user to pass arguments to the application in the build
    //// command itself, like this: `zig build run -- arg1 arg2 etc`
    //if (b.args) |args| {
    //    run_cmd.addArgs(args);
    //}
    //
    //const run_step = b.step("run", "Run the app");
    //run_step.dependOn(&run_cmd.step);
}
