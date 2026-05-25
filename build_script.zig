const std = @import("std");
const builtin = @import("builtin");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;

pub fn BuildScript(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const script_path = b.option([]const u8, "script_path", "path to the script file");
    const script_name = b.option([]const u8, "script_name", "the name of the script");

    const script_step = b.step("script", "Build a script DLL");

    const path = script_path orelse {
        script_step.dependOn(&b.addFail("need -Dscript_path=<path>").step);
        return;
    };
    const name = script_name orelse {
        script_step.dependOn(&b.addFail("need -Dscript_name=<name>").step);
        return;
    };

    const script_dll = b.addLibrary(.{
        .linkage = .dynamic,
        .name = name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = .{ .cwd_relative = path },
            .imports = &.{
                .{ .name = "IM", .module = module },
            },
        }),
    });

    script_step.dependOn(&b.addInstallArtifact(script_dll, .{}).step);
}
