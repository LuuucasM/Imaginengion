const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const windows = target.result.os.tag == .windows;
    const linux = target.result.os.tag == .linux;
    const macos = target.result.os.tag == .macos;

    const nfd_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const nfd_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "NFD",
        .root_module = nfd_mod,
    });

    nfd_mod.addIncludePath(b.path("src/include/"));

    if (windows) {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/nfd_common.c",
                "src/nfd_win.cpp",
            },
        };
        nfd_mod.addCSourceFiles(options);
    }
    if (linux) {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/nfd_common.c",
                "src/nfd_gtk.c",
            },
        };
        nfd_mod.addCSourceFiles(options);
    }
    if (macos) {
        const options = std.Build.Module.AddCSourceFilesOptions{
            .files = &[_][]const u8{
                "src/nfd_common.c",
                "src/nfd_cocoa.m",
            },
        };
        nfd_mod.addCSourceFiles(options);
    }

    if (windows) {
        nfd_mod.linkSystemLibrary("comdlg32", .{ .needed = true });
        nfd_mod.linkSystemLibrary("ole32", .{ .needed = true });
    }

    b.installArtifact(nfd_lib);
}
