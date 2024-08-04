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

    //----------------GLAD-----------------------
    exe.addLibraryPath(.{ .path = "src/Vendor/Glad/zig-out/lib/" });
    exe.addIncludePath(.{ .path = "src/Vendor/Glad/include/" });
    exe.linkSystemLibrary("Glad");

    //--------------------IMGUI-------------------------
    exe.addLibraryPath(.{ .path = "src/Vendor/imgui/zig-out/lib/" });
    exe.addIncludePath(.{ .path = "src/Vendor/imgui/" });
    exe.addIncludePath(.{ .path = "src/Vendor/imgui/imgui/" });
    exe.addIncludePath(.{ .path = "src/Vendor/imgui/generator/output/" });
    const options = std.Build.Module.AddCSourceFilesOptions{
        .files = &[_][]const u8{
            "src/Vendor/imgui/imgui/backends/imgui_impl_glfw.cpp",
            "src/Vendor/imgui/imgui/backends/imgui_impl_opengl3.cpp",
        },
        .flags = &[_][]const u8{
            "-D_CRT_SECURE_NO_WARNINGS",
            "-lstdc++",
            "-D_IMGUI_IMPL_OPENGL_LOADER_GL3W",
        },
    };
    exe.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    exe.addCSourceFiles(options);
    exe.linkSystemLibrary("imgui");

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
