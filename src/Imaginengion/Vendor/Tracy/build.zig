const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const windows = target.result.os.tag == .windows;

    const tracy_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    const tracy_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "Tracy",
        .root_module = tracy_mod,
    });

    tracy_mod.addIncludePath(b.path("public/"));

    const options = std.Build.Module.AddCSourceFilesOptions{
        .files = &[_][]const u8{
            "public/TracyClient.cpp",
        },
        .flags = &[_][]const u8{
            "-DTRACY_ENABLE",
            "-DTRACY_ENABLE_GPU",
            "-DTRACY_ENABLE_OPENGL",
            "-fno-sanitize=all",
        },
    };
    tracy_mod.addCSourceFiles(options);

    if (windows) {
        tracy_mod.linkSystemLibrary("ws2_32", .{});
        tracy_mod.linkSystemLibrary("dbghelp", .{});
    }

    b.installArtifact(tracy_lib);
}
