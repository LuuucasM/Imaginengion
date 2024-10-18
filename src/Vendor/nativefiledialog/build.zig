const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{ .name = "NativeFileDialog", .target = target, .optimize = optimize });
    lib.addIncludePath(.{ .path = "src/include/" });
    const options = switch (builtin.os.tag) {
        .windows => blk: {
            lib.linkSystemLibrary("C++");
            break :blk std.Build.Module.AddCSourceFilesOptions{
                .files = &[_][]const u8{
                    "src/nfd_common.c",
                    "src/nfd_win.cpp",
                },
            };
        },
        .linux => blk: {
            break :blk std.Build.Module.AddCSourceFilesOptions{
                .files = &[_][]const u8{
                    "src/nfd_common.c",
                    "src/nfd_gtk.c",
                },
            };
        },
        .macos => blk: {
            break :blk std.Build.Module.AddCSourceFilesOptions{
                .files = &[_][]const u8{
                    "src/nfd_common.c",
                    "src/nfd_cocoa.m",
                },
            };
        },
        else => @compileError("Do not support the OS given !\n"),
    };
    lib.addCSourceFiles(options);
    lib.linkSystemLibrary("c");
    b.installArtifact(lib);
}
