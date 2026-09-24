const std = @import("std");
const builtin = @import("builtin");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;
const build_shaders = @import("build_shaders.zig");
const build_script = @import("build_script.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const spirv_target = b.resolveTargetQuery(.{
        .cpu_arch = .spirv32,
        .os_tag = .vulkan,
        .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
        .cpu_features_add = std.Target.spirv.featureSet(&.{
            .variable_pointers,
        }),
    });

    //==============================ENGINE MODULE===========================================================
    const engine_module_eng = MakeEngineLib(b, target, optimize, .Full);
    const engine_module_script = MakeEngineLib(b, target, optimize, .Script);
    const engine_module_shader = MakeEngineLib(b, spirv_target, optimize, .Shader);
    //=================================END ENGINE MODULE============================================================

    //==================================OPTIONS============================================================
    const enable_tracy = b.option(bool, "enable-tracy", "Enable tracy") orelse false;
    const tracy_callstack = b.option(u32, "tracy-callstack", "Call stack depth captured with each Tracy memory event, 0 = off") orelse 0;
    const enable_nsight = b.option(bool, "enable-nsight", "Enable nsight") orelse false;
    const no_bin = b.option(bool, "no-bin", "skip emitting binary") orelse false;
    const test_build = b.option(bool, "test-build", "run depends on tests") orelse false;
    const compute_type = b.option(bool, "compute-type", "false == overlay compute, true == game compute") orelse false;

    var debug_build_options = b.addOptions();
    debug_build_options.addOption(bool, "enable_tracy", enable_tracy);
    debug_build_options.addOption(u32, "tracy_callstack", tracy_callstack);
    debug_build_options.addOption(bool, "enable_nsight", enable_nsight);

    engine_module_eng.addOptions("debug_build_options", debug_build_options);
    engine_module_script.addOptions("debug_build_options", debug_build_options);

    var compute_build_options = b.addOptions();
    compute_build_options.addOption(bool, "compute_type", compute_type);
    engine_module_shader.addOptions("compute_build_options", compute_build_options);
    //=======================================END OPTIONS========================================================

    //=========================================SHADER STEP=========================================
    build_shaders.BuildShader(b, engine_module_shader, spirv_target, optimize, engine_module_eng);
    //=========================================END SHADER STEP=====================================

    //=========================================SCRIPT STEP=========================================
    build_script.BuildScript(b, engine_module_script, target, optimize);
    //=========================================END SCRIPT STEP=====================================

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

    //Standalone test files, one per unit under test. Each `*Tests.zig` imports the module it
    //covers, so the module itself carries no test code.
    const unit_test_sources = [_][]const u8{
        "src/Imaginengion/Core/SkipFieldTests.zig",
        "src/Imaginengion/Core/SparseSetTests.zig",
        "src/Imaginengion/Math/MathTypesTests.zig",
    };

    for (unit_test_sources) |test_source| {
        const unit_tests = b.addTest(.{ .root_module = b.createModule(.{
            .target = target,
            .optimize = .Debug,
            .root_source_file = b.path(test_source),
        }) });
        const run_unit_tests = b.addRunArtifact(unit_tests);

        test_step.dependOn(&run_unit_tests.step);
    }

    if (test_build) {
        run_step.dependOn(test_step);
    }

    //Tests that need the whole engine module, because they use EngineContext (see Imaginengion.zig's
    //test block). Kept off `test` while the engine itself does not build, so `zig build test` stays usable.
    const engine_test_step = b.step("test-engine", "Test Engine internals (needs the engine to compile)");

    const engine_tests = b.addTest(.{ .root_module = engine_module_eng });
    const run_engine_tests = b.addRunArtifact(engine_tests);

    engine_test_step.dependOn(&run_engine_tests.step);
    //=========================================END TEST STEP==================================================
}
