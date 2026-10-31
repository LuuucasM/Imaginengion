const std = @import("std");
const builtin = @import("builtin");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;
const ScriptImports = @import("src/Imaginengion/Scripts/ScriptImports.zig");

/// `zig build script -Dscript_path=<file> -Dscript_name=<name> [-Dproject_path=<folder>]`: builds one script into
/// zig-out/bin/<name>.dll. The script file is only its variables, hooks and event handlers; the DLL's root is generated
/// around it, exporting what the engine loads it by (ScriptExport.Exports, made from the script's struct at compile time).
/// With a project, the script imports the project's files by their names (@import("ScoreEvent")), wherever they are in
/// it: the ones it uses are found by reading its imports (ScriptImports), each made a module under its name, and listed
/// in the DLL for the engine to rebuild the script when one changes
pub fn BuildScript(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const script_path = b.option([]const u8, "script_path", "path to the script file");
    const script_name = b.option([]const u8, "script_name", "the name of the script");
    const project_path = b.option([]const u8, "project_path", "the folder of the project the script is in, if it is in one");

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

    var dependencies: []const []const u8 = &.{};
    if (project_path) |project| {
        const collected = FindImports(b, script_step, path, project) catch |err| {
            script_step.dependOn(&b.addFail(b.fmt("couldn't read the project's files for {s}: {s}", .{ path, @errorName(err) })).step);
            return;
        } orelse return;
        dependencies = collected.mDependencies.items;

        //every file imported by name is a module under its name, which the script and every one of them can import
        var named_modules: std.ArrayList(*std.Build.Module) = .empty;
        for (collected.mNamed.items) |named| {
            named_modules.append(b.allocator, b.createModule(.{
                .target = target,
                .optimize = optimize,
                .root_source_file = .{ .cwd_relative = named.Path },
                .imports = &.{.{ .name = "IM", .module = module }},
            })) catch @panic("OOM");
        }
        for (collected.mNamed.items, named_modules.items) |named, named_module| {
            script_module.addImport(named.Name, named_module);
            for (named_modules.items) |other| other.addImport(named.Name, named_module);
        }
    }

    //the symbol has to match ScriptABI.INFO_SYMBOL. The name is only for the script's error messages
    var dependency_list: std.ArrayList(u8) = .empty;
    for (dependencies) |dependency| {
        dependency_list.print(b.allocator, "    \"{f}\",\n", .{std.zig.fmtString(dependency)}) catch @panic("OOM");
    }
    const root_source = b.fmt(
        \\const IM = @import("IM");
        \\const dependencies = [_][*:0]const u8{{
        \\{s}}};
        \\const Exports = IM.ScriptExport.Exports(@import("script"), "{s}", &dependencies);
        \\export fn IM_GetScriptInfo() callconv(.c) *const IM.ScriptABI.ScriptInfo {{
        \\    return &Exports.info;
        \\}}
        \\
    , .{ dependency_list.items, std.fs.path.stem(name) });
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

/// The project files the script at `path` imports, read from its text and theirs. Null, with a failing step added to
/// `script_step` saying why, for two project files with the same name or a name no project file has. The build is set
/// to run this again when any of the files read changes, or any project folder gets a file added or removed
fn FindImports(b: *std.Build, script_step: *std.Build.Step, path: []const u8, project: []const u8) !?ScriptImports.Collected {
    const io = b.graph.io;
    const files = try ScriptImports.FindProjectFiles(b.allocator, io, project);
    for (files.mFolders.items) |folder| b.dependOnDirectoryContents(.{ .cwd_relative = folder });

    if (files.mDuplicate) |duplicate| {
        script_step.dependOn(&b.addFail(b.fmt(
            "two files in the project are named {s}.zig: {s} and {s}. A project file is imported by its name, so each has to have its own",
            .{ duplicate.Name, duplicate.First, duplicate.Second },
        )).step);
        return null;
    }

    const collected = try ScriptImports.Collect(b.allocator, io, path, &files);
    b.dependOnFileContents(.{ .cwd_relative = path });
    for (collected.mDependencies.items) |dependency| b.dependOnFileContents(.{ .cwd_relative = dependency });

    if (collected.mMissing) |missing| {
        script_step.dependOn(&b.addFail(b.fmt(
            "{s} imports \"{s}\", but no file in the project is named {s}.zig",
            .{ missing.In, missing.Name, missing.Name },
        )).step);
        return null;
    }
    return collected;
}
