const std = @import("std");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;

pub fn BuildShader(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const shaders = .{
        .{ "SDFVertShader", "assets/shaders/SDFVertShader.zig", "vert" },
        .{ "SDFFragShader", "assets/shaders/SDFFragShader.zig", "frag" },
    };

    const shaders_step = b.step("shaders", "Build all SPIR-V shaders");

    inline for (shaders) |s| {
        const exe = b.addExecutable(.{
            .name = s[0],
            .root_module = b.createModule(.{
                .root_source_file = b.path(s[1]),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "IM", .module = module },
                },
            }),
        });
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "shaders" } },
        });
        shaders_step.dependOn(&install.step);

        const single_step = b.step(s[2], "Build " ++ s[0] ++ " only");
        single_step.dependOn(&install.step);
    }
}
