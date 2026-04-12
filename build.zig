const std = @import("std");
const builtin = @import("builtin");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_tracy = b.option(bool, "enable-tracy", "Enable the CPU profiler tracy");
    const enable_nsight = b.option(bool, "enable-nsight", "Enable the GPU profiler nvidia nsight");
    const no_bin = b.option(bool, "no-bin", "skip emitting compiler binary") orelse false;
    //function builds the entire engine lib including the dependencies and all
    const engine_lib = MakeEngineLib(b, target, optimize, enable_tracy, enable_nsight) catch @panic("error!!!");

    //make exe
    const editor_exe = b.addExecutable(.{
        .name = "ImaginEditor",
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

    if (no_bin) {
        b.getInstallStep().dependOn(&editor_exe.step);
    } else {
        b.installArtifact(editor_exe);
    }

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    //if (b.args) |args| {
    //    run_cmd.addArgs(args);
    //}

    //================================================RUN STEP=======================================
    const run_cmd = b.addRunArtifact(editor_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run Engine");
    run_step.dependOn(&run_cmd.step);
    //=========================================END RUN STEP====================================

    //=========================================TEST STEP=========================================
    const test_step = b.step("test", "Test Engine");

    //skip field tests
    const skip_field_tests = b.addTest(.{ .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/Imaginengion/Core/SkipField.zig" } },
    }) });
    const run_skip_field_tests = b.addRunArtifact(skip_field_tests);

    test_step.dependOn(&run_skip_field_tests.step);
    //=========================================END TEST STEP==================================================
}
