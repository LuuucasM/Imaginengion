const std = @import("std");
const builtin = @import("builtin");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const script_abs_path = b.option([]const u8, "script_abs_path", "Abs path to script file") orelse @panic("need to pass the abs path for the script!\n");
    const name = std.fs.path.basename(script_abs_path);

    const script_dll = b.addSharedLibrary(.{
        .name = name,
        .optimize = optimize,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = .path(b, script_abs_path),
        }),
    });

    script_dll.addObjectFile(.{ .src_path = .{ .owner = b, .sub_path = "zig-out/lib/Imaginengion.lib" } });

    b.installArtifact(script_dll);
}
