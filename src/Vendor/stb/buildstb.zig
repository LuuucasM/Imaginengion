const std = @import("std");
const Compile = std.Build.Step.Compile;
pub fn Add(exe: *Compile) void {
    const options = std.Build.Module.AddCSourceFilesOptions{
        .files = &[_][]const u8{
            "src/Vendor/stb/stb.c",
        },
        .flags = &[_][]const u8{
            "-std=c99",
        },
    };
    exe.addCSourceFiles(options);
    exe.addIncludePath(.{ .path = "src/Vendor/stb/" });
}
