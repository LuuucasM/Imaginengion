const std = @import("std");
const builtin = @import("builtin");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;
const build_shaders = @import("build_shaders.zig");
const build_script = @import("build_script.zig");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const spirv_target = b.resolveTargetQuery(.{ .cpu_arch = .spirv32, .os_tag = .vulkan, .cpu_features_add = std.Target.spirv.featureSet(&.{
        .variable_pointers,
    }) });

    //==============================ENGINE MODULE===========================================================
    const engine_module_eng = MakeEngineLib(b, target, optimize, .Full);
    const engine_module_script = MakeEngineLib(b, target, optimize, .Script);
    const engine_module_shader = MakeEngineLib(b, spirv_target, optimize, .Shader);
    //=================================END ENGINE MODULE============================================================

    //==================================OPTIONS============================================================
    const enable_tracy = b.option(bool, "enable-tracy", "Enable tracy") orelse false;
    const enable_nsight = b.option(bool, "enable-nsight", "Enable nsight") orelse false;
    const no_bin = b.option(bool, "no-bin", "skip emitting binary") orelse false;
    const test_build = b.option(bool, "test-build", "run depends on tests") orelse false;

    var build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", enable_tracy);
    build_options.addOption(bool, "enable_nsight", enable_nsight);

    engine_module_eng.addOptions("build_options", build_options);
    engine_module_script.addOptions("build_options", build_options);
    //=======================================END OPTIONS========================================================

    //=========================================EDITOR STEP=========================================
    const editor_exe = b.addExecutable(.{
        .name = "ImaginEditor",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/Editor.zig"),
            .imports = &.{
                .{ .name = "IM", .module = engine_module_eng },
            },
        }),
    });

    if (no_bin) {
        b.getInstallStep().dependOn(&editor_exe.step);
    } else {
        b.installArtifact(editor_exe);
    }
    //=========================================END EDITOR STEP=====================================

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

    //=========================================SHADER STEP=========================================
    build_shaders.BuildShader(b, engine_module_shader, spirv_target, optimize);
    //=========================================END SHADER STEP=====================================

    //=========================================SCRIPT STEP=========================================
    build_script.BuildScript(b, engine_module_script, target, optimize);
    //=========================================END SCRIPT STEP=====================================
}
