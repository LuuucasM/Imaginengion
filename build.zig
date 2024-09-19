const std = @import("std");
const builtin = @import("builtin");
const buildglfw = @import("src/Vendor/GLFW/buildglfw.zig");
const buildglad = @import("src/Vendor/Glad/buildglad.zig");
const buildimgui = @import("src/Vendor/imgui/buildimgui.zig");
const buildstb = @import("src/Vendor/stb/buildstb.zig");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //-----------IMAGINENGION---------------
    const exe = b.addExecutable(.{
        .name = "GameEngine",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    //adding c/c++ dependecies
    buildglfw.Add(exe);
    buildglad.Add(exe);
    buildimgui.Add(exe);
    buildstb.Add(exe);

    //--------------SYSTEM LIBRARIES-----------
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("c++");

    if (builtin.os.tag == .windows) {
        exe.linkSystemLibrary("comdlg32");
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
