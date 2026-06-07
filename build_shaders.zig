const std = @import("std");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;

const shaders = .{
    .{ "SDFVertShader", "assets/shaders/SDFVertShader.zig", "vert" },
    .{ "SDFFragShaderOverlay", "assets/shaders/SDFFragShaderOverlay.zig", "frag_overlay" },
    .{ "SDFFragShaderGame", "assets/shaders/SDFFragShaderGame.zig", "frag_game" },
};

pub fn BuildShader(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const shaders_step = b.step("shaders", "Build all SPIR-V shaders");

    const base_module = b.createModule(.{
        .root_source_file = b.path("assets/shaders/SDFFragShaderBase.zig"),
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
        const install = b.addInstallFile(
            obj.getEmittedBin(),
            "shaders/" ++ s[0] ++ ".spv",
        );
        shaders_step.dependOn(&install.step);

        const single_step = b.step(s[2], "Build " ++ s[0] ++ " only");
        single_step.dependOn(&install.step);
    }
}
