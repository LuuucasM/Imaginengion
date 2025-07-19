const std = @import("std");
const builtin = @import("builtin");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_prof = b.option(bool, "enable_profiler", "Enable the profiler");
    //function builds the entire engine lib including the dependencies and all
    const engine_lib = MakeEngineLib(b, target, optimize, enable_prof);

    //make exe
    const editor_exe = b.addExecutable(.{
        .name = "ImaginEditor",
        .optimize = optimize,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Editor.zig" } },
            .imports = &[_]std.Build.Module.Import{
                std.Build.Module.Import{
                    .name = "IM",
                    .module = engine_lib.root_module,
                },
            },
        }),
    });

    //var options = b.addOptions();
    //options.addOption(bool, "enable_profiler", false);
    //editor_exe.root_module.addOptions("build_options", options);

    b.installArtifact(editor_exe);
    const run_cmd = b.addRunArtifact(editor_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
