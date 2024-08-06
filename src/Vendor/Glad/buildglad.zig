const std = @import("std");
const Compile = std.Build.Step.Compile;

pub fn Add(exe: *Compile) void {
    exe.addLibraryPath(.{ .path = "src/Vendor/Glad/zig-out/lib/" });
    exe.addIncludePath(.{ .path = "src/Vendor/Glad/include/" });
    exe.linkSystemLibrary("Glad");
    exe.linkSystemLibrary("c");
}
