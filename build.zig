const std = @import("std");
const builtin = @import("builtin");

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
    //----------------GLFW------------------
    exe.addLibraryPath(.{ .path = "src/Vendor/GLFW/zig-out/lib/" });
    exe.addIncludePath(.{ .path = "src/Vendor/GLFW/include/" });
    exe.linkSystemLibrary("GLFW");

    //--------------SYSTEM LIBRARIES-----------
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("c++");
    switch (builtin.os.tag) {
        .windows => {
            exe.linkSystemLibrary("gdi32");
        },
        else => @compileError("Unsupported os!"),
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
