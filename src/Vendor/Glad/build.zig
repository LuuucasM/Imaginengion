const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{ .name = "Glad", .target = target, .optimize = optimize });
    lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "include/" } });
    const options = std.Build.Module.AddCSourceFilesOptions{
        .files = &[_][]const u8{
            "src/glad.c",
        },
    };
    lib.addCSourceFiles(options);
    lib.linkSystemLibrary("c");
    b.installArtifact(lib);
}
