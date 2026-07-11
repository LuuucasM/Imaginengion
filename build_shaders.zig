const std = @import("std");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;

const shaders = .{
    .{ "SDFVertShader", "src/Imaginengion/EngineAssets/shaders/SDFVertShader.zig", "vert" },
    .{ "SDFFragShaderOverlay", "src/Imaginengion/EngineAssets/shaders/SDFFragShaderOverlay.zig", "frag_overlay" },
    .{ "SDFFragShaderGame", "src/Imaginengion/EngineAssets/shaders/SDFFragShaderGame.zig", "frag_game" },
};

pub fn BuildShader(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, eng_module: *std.Build.Module) void {
    const shaders_step = b.step("shaders", "Build all SPIR-V shaders");

    const base_module = b.createModule(.{
        .root_source_file = b.path("src/Imaginengion/EngineAssets/shaders/SDFFragShaderBase.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "IM", .module = module },
        },
    });

    inline for (shaders) |s| {
        const obj = b.addObject(.{
            .name = s[0],
            .root_module = b.createModule(.{
                .root_source_file = b.path(s[1]),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "FragShaderBase", .module = base_module },
                    .{ .name = "IM", .module = module },
                },
            }),
        });

        eng_module.addAnonymousImport(s[0], .{ .root_source_file = obj.getEmittedBin() });

        const install = b.addInstallFile(
            obj.getEmittedBin(),
            "../src/Imaginengion/EngineAssets/shaders/" ++ s[0] ++ ".spv",
        );
        shaders_step.dependOn(&install.step);

        const single_step = b.step(s[2], "Build " ++ s[0] ++ " only");
        single_step.dependOn(&install.step);
    }
}
