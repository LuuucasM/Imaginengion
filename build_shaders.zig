const std = @import("std");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;

/// Every shader is compiled once per variant (SDFRayMarcher.Features), each embedded under its own name: the plain one
/// does everything, the Lean one only direct shapes and their masks, for passes with no merges and no marched shapes
const variants = .{
    .{ "", false },
    .{ "Lean", true },
};

const shaders = .{
    .{ "SDFComputeGame", "src/Imaginengion/EngineAssets/shaders/SDFComputeGame.zig", "compute_game" },
    .{ "SDFComputeOverlay", "src/Imaginengion/EngineAssets/shaders/SDFComputeOverlay.zig", "compute_overlay" },
};

pub fn BuildShader(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, engine_module_eng: *std.Build.Module) void {
    const shaders_step = b.step("shaders", "Build all SPIR-V shaders");

    const base_module = b.createModule(.{
        .root_source_file = b.path("src/Imaginengion/EngineAssets/shaders/SDFSharedData.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "IM", .module = module },
        },
    });

    inline for (shaders) |s| {
        const single_step = b.step(s[2], "Build " ++ s[0] ++ " only");

        inline for (variants) |v| {
            const name = s[0] ++ v[0];

            //which variant this compile is, read by the shader's main as @import("shader_variant").lean
            const variant_options = b.addOptions();
            variant_options.addOption(bool, "lean", v[1]);

            const obj = b.addExecutable(.{
                .name = name,
                .root_module = b.createModule(.{
                    .root_source_file = b.path(s[1]),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "SDFSharedData", .module = base_module },
                        .{ .name = "IM", .module = module },
                        .{ .name = "shader_variant", .module = variant_options.createModule() },
                    },
                }),
            });

            engine_module_eng.addAnonymousImport(name, .{ .root_source_file = obj.getEmittedBin() });

            const install = b.addInstallFile(
                obj.getEmittedBin(),
                "../src/Imaginengion/EngineAssets/shaders/" ++ name ++ ".spv",
            );
            shaders_step.dependOn(&install.step);
            single_step.dependOn(&install.step);
        }
    }
}
