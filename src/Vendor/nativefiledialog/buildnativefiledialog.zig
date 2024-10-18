const std = @import("std");
const Compile = std.Build.Step.Compile;
const builtin = @import("builtin");

pub fn Add(exe: *Compile) void {
    exe.addLibraryPath(.{ .path = "src/Vendor/nativefiledialog/zig-out/lib/" });
    exe.addIncludePath(.{ .path = "src/Vendor/nativefiledialog/src/include/" });
    exe.linkSystemLibrary("NativeFileDialog");
}
