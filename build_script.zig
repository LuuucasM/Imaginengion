const std = @import("std");
const builtin = @import("builtin");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_tracy = b.option(bool, "enable_tracy", "Enable the CPU profiler tracy");
    const enable_nsight = b.option(bool, "enable_nsight", "Enable the GPU profiler nvidia nsight");

    const script_abs_path = b.option([]const u8, "script_abs_path", "Abs path to script file") orelse @panic("need to pass the abs path for the script!\n");
    const name = std.fs.path.basename(script_abs_path);

    const engine_module = MakeEngineLib(b, target, optimize, enable_tracy, enable_nsight) catch @panic("this cant happen!");

    const script_dll = b.addLibrary(.{
        .linkage = .dynamic,
        .name = name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = script_abs_path } },
            .imports = &.{
                .{ .name = "IM", .module = engine_module },
            },
        }),
    });

    b.installArtifact(script_dll);
}
