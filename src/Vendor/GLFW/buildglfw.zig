const std = @import("std");
const Compile = std.Build.Step.Compile;
const builtin = @import("builtin");

pub fn Add(exe: *Compile) void {
    exe.addLibraryPath(.{ .path = "src/Vendor/GLFW/zig-out/lib/" });
    exe.addIncludePath(.{ .path = "src/Vendor/GLFW/include/" });
    exe.linkSystemLibrary("GLFW");
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("ole32");
}
