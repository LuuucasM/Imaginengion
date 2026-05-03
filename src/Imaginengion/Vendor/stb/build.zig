const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const stb_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    const stb_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "stb",
        .root_module = stb_mod,
    });

    stb_mod.addIncludePath(b.path("./"));

    const options = std.Build.Module.AddCSourceFilesOptions{
        .files = &[_][]const u8{
            "stb.c",
        },
        .flags = &[_][]const u8{
            "-std=c99",
        },
    };
    stb_mod.addCSourceFiles(options);

    b.installArtifact(stb_lib);
}
