const std = @import("std");
const Compile = std.Build.Step.Compile;
pub fn Add(exe: *Compile) void {
    const options = std.Build.Module.AddCSourceFilesOptions{
        .files = &[_][]const u8{
            "src/Vendor/stb/stb.c",
        },
    };
    exe.addCSourceFiles(options);
    exe.addIncludePath(.{ .path = "src/Vendor/stb/" });
}
