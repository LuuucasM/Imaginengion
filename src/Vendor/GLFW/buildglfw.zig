const std = @import("std");
const Compile = std.Build.Step.Compile;

pub fn Add(exe: *Compile) void {
    exe.addLibraryPath(.{ .path = "src/Vendor/GLFW/zig-out/lib/" });
    exe.addIncludePath(.{ .path = "src/Vendor/GLFW/include/" });
    exe.linkSystemLibrary("GLFW");
}
