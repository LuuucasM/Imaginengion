const std = @import("std");
const builtin = @import("builtin");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_tracy = b.option(bool, "enable-tracy", "Enable the CPU profiler tracy") orelse false;
    const enable_nsight = b.option(bool, "enable-nsight", "Enable the GPU profiler nvidia nsight") orelse false;
    const no_bin = b.option(bool, "no-bin", "skip emitting compiler binary") orelse false;
    const test_build = b.option(bool, "test-build", "has run step depend on tests") orelse false;

    var build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", enable_tracy);
    build_options.addOption(bool, "enable_nsight", enable_nsight);

    const engine_module = MakeEngineLib(b, target, optimize, .Full) catch @panic("error!!!");

    engine_module.addOptions("build_options", build_options);

    const editor_exe = b.addExecutable(.{
        .name = "ImaginEditor",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/Editor.zig"),
            .imports = &.{
                .{ .name = "IM", .module = engine_module },
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
        .optimize = .Debug,
        .root_source_file = b.path("src/Imaginengion/Core/SkipField.zig"),
    }) });
    const run_skip_field_tests = b.addRunArtifact(skip_field_tests);

    test_step.dependOn(&run_skip_field_tests.step);

    //LinAlg test_step
    const math_types_tests = b.addTest(.{ .root_module = b.createModule(.{
        .target = target,
        .optimize = .Debug,
        .root_source_file = b.path("src/Imaginengion/Math/MathTypes.zig"),
    }) });

    const run_math_types_test = b.addRunArtifact(math_types_tests);

    test_step.dependOn(&run_math_types_test.step);

    if (test_build) {
        run_step.dependOn(test_step);
    }
    //=========================================END TEST STEP==================================================
}
