const std = @import("std");
const builtin = @import("builtin");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;
const build_shaders = @import("build_shaders.zig");
const build_script = @import("build_script.zig");

/// For a game project's build.zig, which has the engine as a dependency
pub const ProjectBuild = build_script.ProjectBuild;

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
    const engine_module_shader = MakeEngineLib(b, spirv_target, .Debug, .Shader);
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

    //a game packaged to send to someone: its scripts are built ahead of time and shipped with it, since whoever
    //plays it has no zig or engine source to build them with
    const prebuilt_scripts = b.option(bool, "prebuilt-scripts", "load script DLLs built ahead of time instead of compiling them, for a packaged game") orelse false;
    var game_build_options = b.addOptions();
    game_build_options.addOption(bool, "prebuilt_scripts", prebuilt_scripts);
    engine_module_eng.addOptions("game_build_options", game_build_options);
    engine_module_script.addOptions("game_build_options", game_build_options);

    var compute_build_options = b.addOptions();
    compute_build_options.addOption(bool, "compute_type", compute_type);
    engine_module_shader.addOptions("compute_build_options", compute_build_options);
    //=======================================END OPTIONS========================================================

    //=========================================SHADER STEP=========================================
    build_shaders.BuildShader(b, engine_module_shader, spirv_target, .Debug, engine_module_eng);
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

    //zig build editor: only builds it. -Dno-bin only compiles it, to check it builds without writing the exe
    const editor_install = b.addInstallArtifact(editor_exe, .{});
    const editor_step = b.step("editor", "Build the editor");
    if (no_bin) {
        editor_step.dependOn(&editor_exe.step);
        b.getInstallStep().dependOn(&editor_exe.step);
    } else {
        editor_step.dependOn(&editor_install.step);
        b.getInstallStep().dependOn(&editor_install.step);
    }

    //zig build runeditor: builds it and runs it
    const editor_run_cmd = b.addRunArtifact(editor_exe);
    editor_run_cmd.step.dependOn(&editor_install.step);
    const editor_run_step = b.step("runeditor", "Build and run the editor");
    editor_run_step.dependOn(&editor_run_cmd.step);
    //=========================================END EDITOR STEP=====================================

    //=========================================TEST STEP=========================================
    //Tests that need the whole engine module, because they use EngineContext (see Imaginengion.zig's
    //test block). Kept off `test` while the engine itself does not build, so `zig build test` stays usable.
    //This has to stay above any other step that reaches engine files by relative path: ZLS gives a file the imports of
    //the first module to reach it, and only this one has SDL3 and the other C modules
    const engine_test_step = b.step("test-engine", "Test Engine internals (needs the engine to compile)");

    const engine_tests = b.addTest(.{ .root_module = engine_module_eng });
    const run_engine_tests = b.addRunArtifact(engine_tests);

    engine_test_step.dependOn(&run_engine_tests.step);

    const test_step = b.step("test", "Test Engine");

    //All test files live in src/Imaginengion/Tests/, mirroring the folder they cover. Standalone ones
    //(no engine needed) are indexed by UnitTests.zig, which has to sit at the source root so the tests
    //can @import("../...") into the engine sources. New standalone test files go in UnitTests.zig, not here.
    const unit_tests = b.addTest(.{ .root_module = b.createModule(.{
        .target = target,
        .optimize = .Debug,
        .root_source_file = b.path("src/Imaginengion/UnitTests.zig"),
    }) });
    //Standalone tests link no Tracy library, so their zones always compile to nothing
    var unit_test_options = b.addOptions();
    unit_test_options.addOption(bool, "enable_tracy", false);
    unit_test_options.addOption(u32, "tracy_callstack", 0);
    unit_test_options.addOption(bool, "enable_nsight", false);
    unit_tests.root_module.addOptions("debug_build_options", unit_test_options);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    test_step.dependOn(&run_unit_tests.step);

    if (test_build) {
        editor_run_step.dependOn(test_step);
    }
    //=========================================END TEST STEP==================================================
}
