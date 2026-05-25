const std = @import("std");

pub fn MakeOptions(b: *std.Build, engine_module: *std.Build.Module) struct { bool, bool } {
    const enable_tracy = b.option(bool, "enable-tracy", "Enable the CPU profiler tracy") orelse false;
    const enable_nsight = b.option(bool, "enable-nsight", "Enable the GPU profiler nvidia nsight") orelse false;
    const no_bin = b.option(bool, "no-bin", "skip emitting compiler binary") orelse false;
    const test_build = b.option(bool, "test-build", "has run step depend on tests") orelse false;

    var build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", enable_tracy);
    build_options.addOption(bool, "enable_nsight", enable_nsight);

    engine_module.addOptions("build_options", build_options);

    return .{ no_bin, test_build };
}
