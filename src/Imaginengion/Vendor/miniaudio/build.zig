const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mini_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    const mini_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "MiniAudio",
        .root_module = mini_mod,
    });

    mini_mod.addIncludePath(b.path("./"));

    const options = std.Build.Module.AddCSourceFilesOptions{
        .files = &[_][]const u8{
            "miniaudio.c",
        },
        .flags = &[_][]const u8{},
    };

    mini_mod.addCSourceFiles(options);

    b.installArtifact(mini_lib);
}
