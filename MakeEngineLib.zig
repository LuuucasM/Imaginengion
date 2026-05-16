const std = @import("std");
const builtin = @import("builtin");

const RendererBackend = enum {
    OpenGL,
    Vulkan,
};

const LightBuild = enum {
    Script,
    Full,
};

pub fn MakeEngineLib(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, enable_tracy: ?bool, enable_nsight: ?bool, build_type: LightBuild) !*std.Build.Module {
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

    //----------------------------------------------------NFD---------------------------------------------------------
    const nfd_c = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/Imaginengion/Vendor/nativefiledialog/nfd.h"),
    });
    nfd_c.addIncludePath(b.path("src/Imaginengion/Vendor/nativefiledialog/src/include/"));
    //---------------------------------------------------END NFD-------------------------------------------------------------------

    //---------------------------------------------------TRACY-------------------------------------------------------------
    const tracy_c = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/Imaginengion/Vendor/Tracy/tracy.h"),
    });
    tracy_c.addIncludePath(b.path("src/Imaginengion/Vendor/Tracy/public/"));
    //--------------------------------------------------END TRACY-------------------------------------------------------------

    //-------------------------------------------------MINIAUDIO-------------------------------------------------------------
    const mini_c = b.addTranslateC(
        .{
            .optimize = optimize,
            .target = target,
            .root_source_file = b.path("src/Imaginengion/Vendor/miniaudio/mini.h"),
        },
    );
    mini_c.addIncludePath(b.path("src/Imaginengion/Vendor/miniaudio/"));
    //--------------------------------------------------END MINIAUDIO--------------------------------------------------------

    //-------------------------------------------------------------IMGUI---------------------------------------------------------
    const imgui_c = b.addTranslateC(
        .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/Imaginengion/Vendor/imgui/imgui.h"),
            .link_libc = true,
        },
    );

    imgui_c.defineCMacro("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    imgui_c.defineCMacro("CIMGUI_USE_SDL3", "");
    imgui_c.defineCMacro("CIMGUI_USE_SDLGPU", "");
    imgui_c.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");

    imgui_c.addIncludePath(b.path("src/Imaginengion/Vendor/imgui/imgui/"));
    imgui_c.addIncludePath(b.path("src/Imaginengion/Vendor/imgui/imgui/backends/"));
    imgui_c.addIncludePath(b.path("src/Imaginengion/Vendor/imgui"));
    imgui_c.addIncludePath(b.path("src/Imaginengion/Vendor/sdl3/include/"));
    //----------------------------------------------END IMGUI------------------------------------------------------------

    //===============================================SDL3------------------------------------------------------------
    const sdl3_c = b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/Imaginengion/Vendor/sdl3/sdl3.h"),
    });
    sdl3_c.addIncludePath(b.path("src/Imaginengion/Vendor/sdl3/include/"));
    sdl3_c.addIncludePath(b.path("src/Imaginengion/Vendor/sdl3/src/"));
    //================================================END SDL3=========================================================

    //-------------------------------------------------STB-------------------------------------------------------------
    const stb_c = b.addTranslateC(
        .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/Imaginengion/Vendor/stb/stb.h"),
        },
    );
    stb_c.addIncludePath(b.path("src/Imaginengion/Vendor/stb/"));
    //--------------------------------------------------END STB--------------------------------------------------------

    //------------------------------------------------------IMAGINENGION-------------------------------------------------------
    // Module only: wrapping this in `addLibrary` spawned a parallel compile that absorbed
    // vendor C/C++ objects while executables importing this module never linked that `.lib`,
    // giving undefined SDL/ImGui symbols.
    const engine_module = b.addModule(
        "ImaginEngion",
        .{
            .optimize = optimize,
            .target = target,
            .link_libc = true,
            .link_libcpp = true,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Imaginengion.zig" } },
            .imports = &.{
                .{ .name = "SDL3", .module = sdl3_c.createModule() },
                .{ .name = "IMGUI", .module = imgui_c.createModule() },
                .{ .name = "NFD", .module = nfd_c.createModule() },
                .{ .name = "Tracy", .module = tracy_c.createModule() },
                .{ .name = "MiniAudio", .module = mini_c.createModule() },
                .{ .name = "STB", .module = stb_c.createModule() },
            },
        },
    );

    if (build_type == .Full) {
        const nfd_dep = b.dependency("NFD", .{
            .target = target,
            .optimize = optimize,
        });
        const nfd_lib = nfd_dep.artifact("NFD");
        engine_module.linkLibrary(nfd_lib);
        b.installArtifact(nfd_lib);

        const tracy_dep = b.dependency("tracy", .{
            .target = target,
            .optimize = optimize,
        });
        const tracy_lib = tracy_dep.artifact("Tracy");
        engine_module.linkLibrary(tracy_lib);
        b.installArtifact(tracy_lib);

        const mini_dep = b.dependency(
            "MiniAudio",
            .{
                .target = target,
                .optimize = optimize,
            },
        );
        const mini_lib = mini_dep.artifact("MiniAudio");
        engine_module.linkLibrary(mini_lib);
        b.installArtifact(mini_lib);

        const imgui_dep = b.dependency(
            "Imgui",
            .{
                .target = target,
                .optimize = optimize,
            },
        );
        const imgui_lib = imgui_dep.artifact("Imgui");
        engine_module.linkLibrary(imgui_lib);
        b.installArtifact(imgui_lib);

        const sdl3_dep = b.dependency("SDL3", .{
            .target = target,
            .optimize = optimize,
        });
        const sdl3_lib = sdl3_dep.artifact("SDL3");
        engine_module.linkLibrary(sdl3_lib);
        b.installArtifact(sdl3_lib);

        const stb_dep = b.dependency("stb", .{
            .target = target,
            .optimize = optimize,
        });
        const stb_lib = stb_dep.artifact("stb");
        engine_module.linkLibrary(stb_lib);
        b.installArtifact(stb_lib);

        //NOTE: not working for some reaosn just manual compile for now
        //const spirv_target = b.resolveTargetQuery(.{
        //    .cpu_arch = .spirv32,
        //    .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
        //    .os_tag = .vulkan,
        //    .ofmt = .spirv,
        //});
        //
        //const vert_mod = b.createModule(.{
        //    .target = spirv_target,
        //    .optimize = .ReleaseFast,
        //    .root_source_file = b.path("assets/shaders/SDFVertShader.zig"),
        //});
        //const vert_shader = b.addObject(.{
        //    .name = "vert",
        //    .root_module = vert_mod,
        //    .use_llvm = false,
        //    .use_lld = false,
        //});
        //
        //const opts = b.addOptions();
        //opts.addOptionPath("vert_spv", vert_shader.getEmittedBin());
        //engine_module.addOptions("shaders", opts);
    } else {
        engine_module.addLibraryPath(b.path("zig-out/lib/"));
        engine_module.linkSystemLibrary("NFD", .{ .needed = true });
        engine_module.linkSystemLibrary("Tracy", .{ .needed = true });
        engine_module.linkSystemLibrary("MiniAudio", .{ .needed = true });
        engine_module.linkSystemLibrary("Imgui", .{ .needed = true });
        engine_module.linkSystemLibrary("SDL3", .{ .needed = true });
        engine_module.linkSystemLibrary("stb", .{ .needed = true });
    }

    engine_module.addOptions("build_options", build_options);

    return engine_module;
} //-------------------------------------------------------- END IMAGINENGION--------------------------------------------------------------
