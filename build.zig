const std = @import("std");
const builtin = @import("builtin");

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
        .root_module = b.addModule("GLFW", .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/GLFW/glfw.zig" } },
        }),
    });
    glfw_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/GLFW/include/" } });
    {
        const options = switch (builtin.os.tag) {
            .windows => blk: {
                glfw_lib.linkSystemLibrary("gdi32");
                break :blk std.Build.Module.AddCSourceFilesOptions{
                    .files = &[_][]const u8{
                        "src/Imaginengion/Vendor/GLFW/src/context.c",
                        "src/Imaginengion/Vendor/GLFW/src/init.c",
                        "src/Imaginengion/Vendor/GLFW/src/input.c",
                        "src/Imaginengion/Vendor/GLFW/src/monitor.c",
                        "src/Imaginengion/Vendor/GLFW/src/vulkan.c",
                        "src/Imaginengion/Vendor/GLFW/src/window.c",
                        "src/Imaginengion/Vendor/GLFW/src/platform.c",
                        "src/Imaginengion/Vendor/GLFW/src/null_init.c",
                        "src/Imaginengion/Vendor/GLFW/src/null_monitor.c",
                        "src/Imaginengion/Vendor/GLFW/src/null_window.c",
                        "src/Imaginengion/Vendor/GLFW/src/null_joystick.c",
                        "src/Imaginengion/Vendor/GLFW/src/win32_init.c",
                        "src/Imaginengion/Vendor/GLFW/src/win32_joystick.c",
                        "src/Imaginengion/Vendor/GLFW/src/win32_monitor.c",
                        "src/Imaginengion/Vendor/GLFW/src/win32_time.c",
                        "src/Imaginengion/Vendor/GLFW/src/win32_thread.c",
                        "src/Imaginengion/Vendor/GLFW/src/win32_window.c",
                        "src/Imaginengion/Vendor/GLFW/src/wgl_context.c",
                        "src/Imaginengion/Vendor/GLFW/src/egl_context.c",
                        "src/Imaginengion/Vendor/GLFW/src/osmesa_context.c",
                        "src/Imaginengion/Vendor/GLFW/src/win32_module.c",
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
                        "src/Imaginengion/Vendor/GLFW/src/context.c",
                        "src/Imaginengion/Vendor/GLFW/src/init.c",
                        "src/Imaginengion/Vendor/GLFW/src/input.c",
                        "src/Imaginengion/Vendor/GLFW/src/monitor.c",
                        "src/Imaginengion/Vendor/GLFW/src/vulkan.c",
                        "src/Imaginengion/Vendor/GLFW/src/window.c",
                        "src/Imaginengion/Vendor/GLFW/src/platform.c",
                        "src/Imaginengion/Vendor/GLFW/src/null_init.c",
                        "src/Imaginengion/Vendor/GLFW/src/null_monitor.c",
                        "src/Imaginengion/Vendor/GLFW/src/null_window.c",
                        "src/Imaginengion/Vendor/GLFW/src/null_joystick.c",
                        "src/Imaginengion/Vendor/GLFW/src/x11_init.c",
                        "src/Imaginengion/Vendor/GLFW/src/x11_monitor.c",
                        "src/Imaginengion/Vendor/GLFW/src/xx1_window.c",
                        "src/Imaginengion/Vendor/GLFW/src/xkb_unicode.c",
                        "src/Imaginengion/Vendor/GLFW/src/posix_time.c",
                        "src/Imaginengion/Vendor/GLFW/src/posix_thread.c",
                        "src/Imaginengion/Vendor/GLFW/src/glx_context.c",
                        "src/Imaginengion/Vendor/GLFW/src/egl_context.c",
                        "src/Imaginengion/Vendor/GLFW/src/osmesa_context.c",
                        "src/Imaginengion/Vendor/GLFW/src/linux_joystick.c",
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
    //-------------------------------------------------END GLFW----------------------------------------------------
    //---------------------------------------------------GLAD----------------------------------------------
    const glad_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "GLAD",
        .root_module = b.addModule("GLAD", .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/Glad/glad.zig" } },
        }),
    });
    glad_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/Glad/include/" } });
    {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/Imaginengion/Vendor/Glad/src/glad.c",
            },
        };
        glad_lib.addCSourceFiles(options);
    }
    //------------------------------------------------------------END GLAD-----------------------------------------------------------------
    //-------------------------------------------------------------IMGUI---------------------------------------------------------
    const imgui_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "IMGUI",
        .root_module = b.addModule("IMGUI", .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/imgui/imgui.zig" } },
            .imports = &[_]std.Build.Module.Import{
                .{
                    .name = "GLFW",
                    .module = glfw_lib.root_module,
                },
            },
        }),
    });
    imgui_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/imgui/" } });
    imgui_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/imgui/imgui/" } });
    {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/Imaginengion/Vendor/imgui/imgui/imgui.cpp",
                "src/Imaginengion/Vendor/imgui/imgui/imgui_demo.cpp",
                "src/Imaginengion/Vendor/imgui/imgui/imgui_draw.cpp",
                "src/Imaginengion/Vendor/imgui/imgui/imgui_tables.cpp",
                "src/Imaginengion/Vendor/imgui/imgui/imgui_widgets.cpp",
                "src/Imaginengion/Vendor/imgui/ImGuizmo/ImGuizmo.cpp",
                "src/Imaginengion/Vendor/imgui/cimgui.cpp",
                "src/Imaginengion/Vendor/imgui/cimguizmo.cpp",
                "src/Imaginengion/Vendor/imgui/imgui/backends/imgui_impl_opengl3.cpp",
                "src/Imaginengion/Vendor/imgui/imgui/backends/imgui_impl_glfw.cpp",
            },
            .flags = &[_][]const u8{
                "-D_CRT_SECURE_NO_WARNINGS",
                "-lstdc++",
                "-D_IMGUI_IMPL_OPENGL_LOADER_GL3W",
            },
        };
        imgui_lib.addCSourceFiles(options);
    }
    //----------------------------------------------END IMGUI------------------------------------------------------------
    //----------------------------------------------------NFD---------------------------------------------------------
    const nfd_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "NFD",
        .root_module = b.addModule("NFD", .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/nativefiledialog/nfd.zig" } },
        }),
    });
    nfd_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/nativefiledialog/src/include/" } });
    {
        const options = switch (builtin.os.tag) {
            .windows => blk: {
                break :blk std.Build.Module.AddCSourceFilesOptions{
                    .files = &[_][]const u8{
                        "src/Imaginengion/Vendor/nativefiledialog/src/nfd_common.c",
                        "src/Imaginengion/Vendor/nativefiledialog/src/nfd_win.cpp",
                    },
                };
            },
            .linux => blk: {
                break :blk std.Build.Module.AddCSourceFilesOptions{
                    .files = &[_][]const u8{
                        "src/Imaginengion/Vendor/nativefiledialog/src/nfd_common.c",
                        "src/Imaginengion/Vendor/nativefiledialog/src/nfd_gtk.c",
                    },
                };
            },
            .macos => blk: {
                break :blk std.Build.Module.AddCSourceFilesOptions{
                    .files = &[_][]const u8{
                        "src/Imaginengion/Vendor/nativefiledialog/src/nfd_common.c",
                        "src/Imaginengion/Vendor/nativefiledialog/src/nfd_cocoa.m",
                    },
                };
            },
            else => @compileError("Do not support the OS given !\n"),
        };
        nfd_lib.addCSourceFiles(options);
    }
    //---------------------------------------------------END NFD-------------------------------------------------------------------
    //------------------------------------------------------IMAGINENGION-------------------------------------------------------
    const engine_lib = b.addLibrary(.{ .linkage = .static, .name = "Imaginengion", .root_module = b.addModule(
        "ImaginEngion",
        .{
            .optimize = optimize,
            .target = target,
            .link_libc = true,
            .link_libcpp = true,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion.zig" } },
            .imports = &[_]std.Build.Module.Import{
                std.Build.Module.Import{
                    .name = "GLFW",
                    .module = glfw_lib.root_module,
                },
                std.Build.Module.Import{
                    .name = "GLAD",
                    .module = glad_lib.root_module,
                },
                std.Build.Module.Import{
                    .name = "IMGUI",
                    .module = imgui_lib.root_module,
                },
                std.Build.Module.Import{
                    .name = "NFD",
                    .module = nfd_lib.root_module,
                },
            },
        },
    ) });
    //-------------------------------------------------------- END IMAGINENGION--------------------------------------------------------------
    //--------------------------------------------------------------STB----------------------------------------------------------------------
    {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/Imaginengion/Vendor/stb/stb.c",
            },
            .flags = &[_][]const u8{
                "-std=c99",
            },
        };
        engine_lib.addCSourceFiles(options);
        engine_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/stb/" } });
    }
    //------------------------------------------------------------END STB----------------------------------------------------------------------

    if (builtin.os.tag == .windows) {
        glfw_lib.linkSystemLibrary("gdi32");
        imgui_lib.linkSystemLibrary("gdi32");

        nfd_lib.linkSystemLibrary("comdlg32");
        nfd_lib.linkSystemLibrary("ole32");
    }

    const editor_exe = b.addExecutable(.{
        .name = "ImaginEditor",
        .optimize = optimize,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Editor.zig" } },
            .imports = &[_]std.Build.Module.Import{
                std.Build.Module.Import{
                    .name = "IM",
                    .module = engine_lib.root_module,
                },
            },
        }),
    });

    const run_cmd = b.addRunArtifact(editor_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
