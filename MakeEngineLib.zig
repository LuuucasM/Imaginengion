const std = @import("std");
const builtin = @import("builtin");

const RendererBackend = enum {
    OpenGL,
    Vulkan,
};

pub fn MakeEngineLib(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, enable_tracy: ?bool, enable_nsight: ?bool) !*std.Build.Step.Compile {
    //---------------------------BUILD OPTIONS--------------------------
    var build_options = b.addOptions();
    if (enable_tracy != null and enable_tracy.? == true) {
        build_options.addOption(bool, "enable_tracy", true);
    } else {
        build_options.addOption(bool, "enable_tracy", false);
    }
    if (enable_nsight != null and enable_nsight.? == true) {
        build_options.addOption(bool, "enable_nsight", true);
    } else {
        build_options.addOption(bool, "enable_nsight", false);
    }
    //--------------------------END BUILD OPTIONS------------------------

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
    imgui_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/sdl3/include/" } });

    //add c source files
    {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/Imaginengion/Vendor/imgui/imgui/imgui.cpp",
                "src/Imaginengion/Vendor/imgui/imgui/imgui_demo.cpp",
                "src/Imaginengion/Vendor/imgui/imgui/imgui_draw.cpp",
                "src/Imaginengion/Vendor/imgui/imgui/imgui_tables.cpp",
                "src/Imaginengion/Vendor/imgui/imgui/imgui_widgets.cpp",

                "src/Imaginengion/Vendor/imgui/imgui/backends/imgui_impl_sdl3.cpp",
                "src/Imaginengion/Vendor/imgui/imgui/backends/imgui_impl_sdlgpu3.cpp",

                "src/Imaginengion/Vendor/imgui/cimgui.cpp",
            },
            .flags = &[_][]const u8{
                "-D_CRT_SECURE_NO_WARNINGS",
                if (builtin.os.tag == .windows) "-lstdc++" else "",
                "-DCIMGUI_USE_SDL3",
                "-DCIMGUI_USE_SDLGPU",
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

    //-------------------------------------------------MINIAUDIO-------------------------------------------------------------
    //make library
    const miniaudio_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "MiniAudio",
        .root_module = b.addModule("MiniAudio", .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/miniaudio/MiniAudio.zig" } },
        }),
    });

    //add include paths
    miniaudio_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/miniaudio" } });

    //add c source files
    {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/Imaginengion/Vendor/miniaudio/miniaudio.c",
            },
            .flags = &[_][]const u8{},
        };
        miniaudio_lib.addCSourceFiles(options);
    }
    //--------------------------------------------------END MINIAUDIO--------------------------------------------------------

    //-------------------------------------------------SDL 3-------------------------------------------------------------
    //make library
    const sdl3_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "SDL3",
        .root_module = b.addModule("SDL3", .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/sdl3/SDL3.zig" } },
        }),
    });

    //add include paths
    sdl3_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/sdl3/include" } });
    sdl3_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/sdl3/src" } });
    sdl3_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/sdl3/include/build_config" } });
    sdl3_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/egl" } });

    //add c source files
    {
        var sources = std.ArrayList([]const u8).empty;
        defer sources.deinit(b.allocator);

        var src_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src", .{ .iterate = true });
        defer src_dir.close();
        var src_iter = src_dir.iterate();
        while (try src_iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/{s}", .{entry.name}));
            }
        }

        var core_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src/core", .{ .iterate = true });
        defer core_dir.close();
        var core_iter = core_dir.iterate();
        while (try core_iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/core/{s}", .{entry.name}));
            }
        }

        var stdlib_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src/stdlib", .{ .iterate = true });
        defer stdlib_dir.close();
        var stdlib_iter = stdlib_dir.iterate();
        while (try stdlib_iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/stdlib/{s}", .{entry.name}));
            }
        }

        var events_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src/events", .{ .iterate = true });
        defer events_dir.close();
        var events_iter = events_dir.iterate();
        while (try events_iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/events/{s}", .{entry.name}));
            }
        }

        var misc_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src/misc", .{ .iterate = true });
        defer misc_dir.close();
        var misc_iter = misc_dir.iterate();
        while (try misc_iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/misc/{s}", .{entry.name}));
            }
        }

        var thread_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src/thread", .{ .iterate = true });
        defer thread_dir.close();
        var thread_iter = thread_dir.iterate();
        while (try thread_iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/thread/{s}", .{entry.name}));
            }
        }

        var timer_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src/timer", .{ .iterate = true });
        defer timer_dir.close();
        var timer_iter = timer_dir.iterate();
        while (try timer_iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/timer/{s}", .{entry.name}));
            }
        }

        var video_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src/video", .{ .iterate = true });
        defer video_dir.close();
        var video_iter = video_dir.iterate();
        while (try video_iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/video/{s}", .{entry.name}));
            }
        }

        var gpu_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src/gpu", .{ .iterate = true });
        defer gpu_dir.close();
        var gpu_iter = gpu_dir.iterate();
        while (try gpu_iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/gpu/{s}", .{entry.name}));
            }
        }

        if (target.result.os.tag == .windows) {
            var core_windows_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src/core/windows", .{ .iterate = true });
            defer core_windows_dir.close();
            var core_windows_iter = core_windows_dir.iterate();
            while (try core_windows_iter.next()) |entry| {
                if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                    try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/core/windows/{s}", .{entry.name}));
                }
            }

            var thread_windows_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src/thread/windows", .{ .iterate = true });
            defer thread_windows_dir.close();
            var thread_windows_iter = thread_windows_dir.iterate();
            while (try thread_windows_iter.next()) |entry| {
                if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                    try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/thread/windows/{s}", .{entry.name}));
                }
            }

            var timer_windows_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src/timer/windows", .{ .iterate = true });
            defer timer_windows_dir.close();
            var timer_windows_iter = timer_windows_dir.iterate();
            while (try timer_windows_iter.next()) |entry| {
                if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                    try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/timer/windows/{s}", .{entry.name}));
                }
            }

            var video_windows_dir = try std.fs.cwd().openDir("src/Imaginengion/Vendor/sdl3/src/video/windows", .{ .iterate = true });
            defer video_windows_dir.close();
            var video_windows_iter = video_windows_dir.iterate();
            while (try video_windows_iter.next()) |entry| {
                if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".c")) {
                    try sources.append(b.allocator, b.fmt("src/Imaginengion/Vendor/sdl3/src/video/windows/{s}", .{entry.name}));
                }
            }
        }

        sdl3_lib.addCSourceFiles(.{
            .files = sources.items,
            .flags = &[_][]const u8{
                "-DHAVE_LIBC",
                "-D_WINDOWS",
                "-DWIN32",
                "-D_CRT_SECURE_NO_WARNINGS",
                "-DSDL_VIDEO_VULKAN=1",
                "-DSDL_GPU=1",
            },
        });
    }
    if (target.result.os.tag == .windows) {
        sdl3_lib.linkSystemLibrary("user32");
        sdl3_lib.linkSystemLibrary("gdi32");
        sdl3_lib.linkSystemLibrary("shell32");
        sdl3_lib.linkSystemLibrary("ole32");
        sdl3_lib.linkSystemLibrary("oleaut32");
        sdl3_lib.linkSystemLibrary("uuid");
        sdl3_lib.linkSystemLibrary("version");
        sdl3_lib.linkSystemLibrary("winmm");
        sdl3_lib.linkSystemLibrary("imm32");
        sdl3_lib.linkSystemLibrary("setupapi");
        sdl3_lib.linkSystemLibrary("advapi32");
    }
    //--------------------------------------------------END SDL 3--------------------------------------------------------

    //-------------------------------------------------STB-------------------------------------------------------------
    //make library
    const stb_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "stb",
        .root_module = b.addModule("stb", .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/stb/stb.zig" } },
        }),
    });

    //add include paths
    stb_lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Vendor/stb" } });

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
        stb_lib.addCSourceFiles(options);
    }
    //--------------------------------------------------END STB--------------------------------------------------------

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
                .imports = &[_]std.Build.Module.Import{ std.Build.Module.Import{
                    .name = "SDL3",
                    .module = sdl3_lib.root_module,
                }, std.Build.Module.Import{
                    .name = "IMGUI",
                    .module = imgui_lib.root_module,
                }, std.Build.Module.Import{
                    .name = "NFD",
                    .module = nfd_lib.root_module,
                }, std.Build.Module.Import{
                    .name = "Tracy",
                    .module = tracy_lib.root_module,
                }, std.Build.Module.Import{
                    .name = "MiniAudio",
                    .module = miniaudio_lib.root_module,
                }, std.Build.Module.Import{
                    .name = "STB",
                    .module = stb_lib.root_module,
                } },
            },
        ),
    });

    // build.zig
    const vulkan_sdk = std.process.getEnvVarOwned(b.allocator, "VULKAN_SDK") catch @panic("VULKAN_SDK not set");
    engine_lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ vulkan_sdk, "Include" }) });

    engine_lib.root_module.addOptions("build_options", build_options);

    //return final engine_lib
    return engine_lib;
} //-------------------------------------------------------- END IMAGINENGION--------------------------------------------------------------
