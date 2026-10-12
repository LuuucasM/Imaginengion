const std = @import("std");
const builtin = @import("builtin");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;

/// `zig build script -Dscript_path=<file> -Dscript_name=<name>`: builds one script into zig-out/bin/<name>.dll. The
/// script file is only its variables and hooks; the DLL's root is generated around it, exporting what the engine loads
/// it by (ScriptExport.Exports, made from the script's struct at compile time)
pub fn BuildScript(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const script_path = b.option([]const u8, "script_path", "path to the script file");
    const script_name = b.option([]const u8, "script_name", "the name of the script");

    const script_step = b.step("script", "Build a script DLL");

    const path = script_path orelse {
        script_step.dependOn(&b.addFail("need -Dscript_path=<path>").step);
        return;
    };
    const name = script_name orelse {
        script_step.dependOn(&b.addFail("need -Dscript_name=<name>").step);
        return;
    };

    const script_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .cwd_relative = path },
        .imports = &.{
            .{ .name = "IM", .module = module },
        },
    });

    //the symbol has to match ScriptABI.INFO_SYMBOL. The name is only for the script's error messages
    const root_source = b.fmt(
        \\const IM = @import("IM");
        \\const Exports = IM.ScriptExport.Exports(@import("script"), "{s}");
        \\export fn IM_GetScriptInfo() callconv(.c) *const IM.ScriptABI.ScriptInfo {{
        \\    return &Exports.info;
        \\}}
        \\
    , .{std.fs.path.stem(name)});
    const root_file = b.addWriteFiles().add("script_root.zig", root_source);

    const script_dll = b.addLibrary(.{
        .linkage = .dynamic,
        .name = name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = root_file,
            .imports = &.{
                .{ .name = "IM", .module = module },
                .{ .name = "script", .module = script_module },
            },
        }),
    });

    script_step.dependOn(&b.addInstallArtifact(script_dll, .{}).step);
}
