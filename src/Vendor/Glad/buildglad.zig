const std = @import("std");
const Compile = std.Build.Step.Compile;

pub fn Add(exe: *Compile, b: *std.Build) void {
    exe.addLibraryPath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/Glad/zig-out/lib/" } });
    exe.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/Glad/include/" } });
    exe.linkSystemLibrary("Glad");
}
