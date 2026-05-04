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

    const script_path = b.option([]const u8, "script_path", "path to the script file") orelse @panic("need to pass the path for the script!\n");
    const script_name = b.option([]const u8, "script_name", "the name of the script") orelse @panic("need to pass the script name!\n");

    const engine_module = MakeEngineLib(b, target, optimize, enable_tracy, enable_nsight, .Script) catch @panic("this cant happen!");

    const script_dll = b.addLibrary(.{
        .linkage = .dynamic,
        .name = script_name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = .{ .cwd_relative = script_path },
            .imports = &.{
                .{ .name = "IM", .module = engine_module },
            },
        }),
    });

    b.installArtifact(script_dll);
}
