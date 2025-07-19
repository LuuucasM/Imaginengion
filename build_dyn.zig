const std = @import("std");
const builtin = @import("builtin");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_prof = b.option(bool, "enable_profiler", "Enable the profiler");

    const script_abs_path = b.option([]const u8, "script_abs_path", "Abs path to script file") orelse @panic("need to pass the abs path for the script!\n");
    const name = std.fs.path.basename(script_abs_path);

    const engine_lib = MakeEngineLib(b, target, optimize, enable_prof);

    const script_dll = b.addLibrary(.{
        .linkage = .dynamic,
        .name = name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = script_abs_path } },
            .imports = &[_]std.Build.Module.Import{
                std.Build.Module.Import{
                    .name = "IM",
                    .module = engine_lib.root_module,
                },
            },
        }),
    });

    b.installArtifact(script_dll);
}
