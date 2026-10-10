const std = @import("std");

const RendererBackend = enum {
    OpenGL,
    Vulkan,
};

const LightBuild = enum {
    Script,
    Full,
    Shader,
};

pub fn MakeEngineLib(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, build_type: LightBuild) *std.Build.Module {
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

    //===============================================SDL3------------------------------------------------------------
    const sdl3_c = b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/Imaginengion/Vendor/sdl3/sdl3.h"),
    });
    sdl3_c.addIncludePath(b.path("src/Imaginengion/Vendor/sdl3/include/"));
    sdl3_c.addIncludePath(b.path("src/Imaginengion/Vendor/sdl3/src/"));
    const vulkan_sdk = b.graph.environ_map.get("VULKAN_SDK");
    if (vulkan_sdk) |sdk_path| {
        std.log.info("[BUILD] VulkanSDK at: {s}", .{sdk_path});
        const vulkan_path = b.graph.cwdRelativePath(b.fmt("{s}/include", .{sdk_path}));
        sdl3_c.addIncludePath(vulkan_path);
    } else {
        std.log.err("Could not find VulkanSDK. Try sourcing setup-env.sh", .{});
    }

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
    // giving undefined SDL symbols.
    const engine_module = switch (build_type) {
        .Full => b.addModule(
            "ImaginEngionEngine",
            .{
                .optimize = optimize,
                .target = target,
                .link_libc = true,
                .link_libcpp = true,
                .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Imaginengion.zig" } },
                .imports = &.{
                    .{ .name = "SDL3", .module = sdl3_c.createModule() },
                    .{ .name = "NFD", .module = nfd_c.createModule() },
                    .{ .name = "Tracy", .module = tracy_c.createModule() },
                    .{ .name = "MiniAudio", .module = mini_c.createModule() },
                    .{ .name = "STB", .module = stb_c.createModule() },
                },
            },
        ),
        .Script => b.addModule(
            "ImaginEngionScript",
            .{
                .optimize = optimize,
                .target = target,
                .link_libc = true,
                .link_libcpp = true,
                .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Imaginengion.zig" } },
                .imports = &.{
                    .{ .name = "SDL3", .module = sdl3_c.createModule() },
                    .{ .name = "NFD", .module = nfd_c.createModule() },
                    .{ .name = "Tracy", .module = tracy_c.createModule() },
                    .{ .name = "MiniAudio", .module = mini_c.createModule() },
                    .{ .name = "STB", .module = stb_c.createModule() },
                },
            },
        ),
        .Shader => b.addModule(
            "ImaginEngionShader",
            .{
                .optimize = optimize,
                .target = target,
                .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/ImagineShaders.zig" } },
            },
        ),
    };

    switch (build_type) {
        .Full => {
            const nfd_dep = b.dependency("NFD", .{
                .target = target,
                .optimize = optimize,
            });
            const nfd_lib = nfd_dep.artifact("NFD");
            engine_module.linkLibrary(nfd_lib);

            const tracy_dep = b.dependency("tracy", .{
                .target = target,
                .optimize = optimize,
            });
            const tracy_lib = tracy_dep.artifact("Tracy");
            engine_module.linkLibrary(tracy_lib);

            const mini_dep = b.dependency(
                "MiniAudio",
                .{
                    .target = target,
                    .optimize = optimize,
                },
            );
            const mini_lib = mini_dep.artifact("MiniAudio");
            engine_module.linkLibrary(mini_lib);

            const sdl3_dep = b.dependency("SDL3", .{
                .target = target,
                .optimize = optimize,
            });
            const sdl3_lib = sdl3_dep.artifact("SDL3");
            engine_module.linkLibrary(sdl3_lib);

            const stb_dep = b.dependency("stb", .{
                .target = target,
                .optimize = optimize,
            });
            const stb_lib = stb_dep.artifact("stb");
            engine_module.linkLibrary(stb_lib);
        },
        // Scripts link none of the C libs: script-callable code never calls them, and linking them from zig-out/lib
        // kept Zig from ever caching a script's compile
        else => {},
    }

    return engine_module;
} //-------------------------------------------------------- END IMAGINENGION--------------------------------------------------------------
