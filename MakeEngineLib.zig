const std = @import("std");
const builtin = @import("builtin");

const RendererBackend = enum {
    OpenGL,
    Vulkan,
};

pub fn MakeEngineLib(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, enable_prof: ?bool) *std.Build.Step.Compile {
    //---------------------------BUILD OPTIONS--------------------------
    var build_options = b.addOptions();
    if (enable_prof != null and enable_prof.? == true) {
        build_options.addOption(bool, "enable_profiler", true);
    } else {
        build_options.addOption(bool, "enable_profiler", false);
    }
    //--------------------------END BUILD OPTIONS------------------------

    //--------------------------------------------------GLFW---------------------------------------------------------------------------
    //make library
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

    //add include paths
    glfw_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/GLFW/include/" } });

    //add c source files
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

    //add system libraries
    if (builtin.os.tag == .windows) {
        glfw_lib.linkSystemLibrary("gdi32");
    }
    //-------------------------------------------------END GLFW----------------------------------------------------

    //---------------------------------------------------GLAD----------------------------------------------
    //make lib
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
    //add include paths
    glad_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/Glad/include/" } });

    //add c source files
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
    //make library
    const imgui_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "IMGUI",
        .root_module = b.addModule("IMGUI", .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/imgui/imgui.zig" } },
        }),
    });

    //add include paths
    imgui_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/imgui/" } });
    imgui_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/imgui/imgui/" } });
    imgui_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/GLFW/include/" } });
    imgui_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/Glad/include/" } });

    //add c source files
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
            },
            .flags = &[_][]const u8{
                "-D_CRT_SECURE_NO_WARNINGS",
                if (builtin.os.tag == .windows) "-lstdc++" else "",
                "-D_IMGUI_IMPL_OPENGL_LOADER_GL3W",
            },
        };
        imgui_lib.addCSourceFiles(options);
    }

    //add system libraries
    if (builtin.os.tag == .windows) {
        imgui_lib.linkSystemLibrary("gdi32");
    }
    //----------------------------------------------END IMGUI------------------------------------------------------------

    //----------------------------------------------------NFD---------------------------------------------------------
    //make library
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

    //add include paths
    nfd_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/nativefiledialog/src/include/" } });

    //add c source files
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

    //add system libraries
    if (builtin.os.tag == .windows) {
        nfd_lib.linkSystemLibrary("comdlg32");
        nfd_lib.linkSystemLibrary("ole32");
    }
    //---------------------------------------------------END NFD-------------------------------------------------------------------

    //---------------------------------------------------TRACY-------------------------------------------------------------
    //make library
    const tracy_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "Tracy",
        .root_module = b.addModule("Tracy", .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/Tracy/tracy.zig" } },
        }),
    });

    //add include paths
    tracy_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/Tracy/public/" } });

    //add c source files
    {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/Imaginengion/Vendor/Tracy/public/TracyClient.cpp",
            },
            .flags = &[_][]const u8{
                "-DTRACY_ENABLE",
                "-DTRACY_ENABLE_GPU",
                "-DTRACY_ENABLE_OPENGL",
                "-fno-sanitize=all",
            },
        };
        tracy_lib.addCSourceFiles(options);
    }

    if (builtin.os.tag == .windows) {
        tracy_lib.linkSystemLibrary("ws2_32");
        tracy_lib.linkSystemLibrary("dbghelp");
    }
    //--------------------------------------------------END TRACY-------------------------------------------------------------

    //------------------------------------------------------IMAGINENGION-------------------------------------------------------
    //make library
    const engine_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "Imaginengion",
        .root_module = b.addModule(
            "ImaginEngion",
            .{
                .optimize = optimize,
                .target = target,
                .link_libc = true,
                .link_libcpp = true,
                .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Imaginengion.zig" } },
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
                    std.Build.Module.Import{
                        .name = "Tracy",
                        .module = tracy_lib.root_module,
                    },
                },
            },
        ),
    });

    engine_lib.root_module.addOptions("build_options", build_options);

    //add include paths
    engine_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/imgui/imgui/" } });
    engine_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/GLFW/include/" } });
    engine_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/stb/" } });

    //add c source files
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
    }
    {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/Imaginengion/Vendor/imgui/imgui/backends/imgui_impl_glfw.cpp",
                "src/Imaginengion/Vendor/imgui/imgui/backends/imgui_impl_opengl3.cpp",
            },
            .flags = &[_][]const u8{
                "-D_CRT_SECURE_NO_WARNINGS",
                "-DIMGUI_IMPL_API=extern\"C\"",
                "-DIMGUI_IMPL_OPENGL_LOADER_GLAD",
                "-includesrc/Imaginengion/Vendor/Glad/include/glad/glad.h",
            },
        };
        engine_lib.addCSourceFiles(options);
    }

    //return final engine_lib
    return engine_lib;
} //-------------------------------------------------------- END IMAGINENGION--------------------------------------------------------------
