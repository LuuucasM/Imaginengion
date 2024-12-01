const std = @import("std");
const Compile = std.Build.Step.Compile;
const builtin = @import("builtin");

pub fn Add(exe: *Compile, b: *std.Build) void {
    exe.addLibraryPath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/nativefiledialog/zig-out/lib/" } });
    exe.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/Vendor/nativefiledialog/src/include/" } });
    exe.linkSystemLibrary("NativeFileDialog");
}
