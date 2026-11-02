const std = @import("std");
const builtin = @import("builtin");
const MakeEngineLib = @import("MakeEngineLib.zig").MakeEngineLib;
const ScriptImports = @import("src/Imaginengion/Scripts/ScriptImports.zig");
const EngineFiles = @import("src/Imaginengion/GameBuild/EngineFiles.zig");
const ProjectWalk = @import("src/Imaginengion/GameBuild/ProjectWalk.zig");

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

/// What a game project's build.zig calls (Project.WriteBuildFiles writes it), run from the project's folder:
/// - `zig build check`: every .zig file in the project compiles. It's what ZLS knows the files' imports from, which it
///   only reads from a compile step in the build.zig above a file
/// - `zig build game`, or just `zig build`: the game in zig-out/<name>/, a folder that runs with no zig or engine source,
///   holding only what ProjectWalk finds it needs. Anything else in that folder is deleted, so it's no place to keep files
/// - `zig build rungame`: builds the game and runs it
pub fn ProjectBuild(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    //a project's build is for playing unless asked for something else
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Build mode, fast if not given") orelse .fast;
    const engine = b.dependency("GameEngine", .{ .target = target, .optimize = optimize, .@"packaged-game" = true });

    const check_step = b.step("check", "Check that the project's files compile");
    const game_step = b.step("game", "Build the game into zig-out/<name>/");
    const run_step = b.step("rungame", "Build the game and run it");
    b.getInstallStep().dependOn(game_step);

    AddProjectSteps(b, engine, check_step, game_step, run_step, target, optimize) catch |err| {
        const fail = b.addFail(b.fmt("couldn't read the project's files: {s}", .{@errorName(err)}));
        check_step.dependOn(&fail.step);
        game_step.dependOn(&fail.step);
    };
}

fn AddProjectSteps(b: *std.Build, engine: *std.Build.Dependency, check_step: *std.Build.Step, game_step: *std.Build.Step, run_step: *std.Build.Step, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    const engine_module = engine.module("ImaginEngionScript");
    const project = try b.root.root_dir.handle.realPathFileAlloc(b.graph.io, ".", b.allocator);
    const files = try ScriptImports.FindProjectFiles(b.allocator, b.graph.io, project);
    for (files.mFolders.items) |folder| b.dependOnDirectoryContents(.{ .cwd_relative = folder });
    if (FailOnDuplicate(b, check_step, &files)) return;
    if (FailOnDuplicate(b, game_step, &files)) return;

    var names: std.ArrayList([]const u8) = .empty;
    var modules: std.ArrayList(*std.Build.Module) = .empty;
    const roots = b.addWriteFiles();
    var iter = files.mByName.iterator();
    while (iter.next()) |file| {
        const name = file.key_ptr.*;
        const module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            //from the project's folder: ZLS only finds a file with a path that starts there
            .root_source_file = b.path(file.value_ptr.*[project.len + 1 ..]),
            .imports = &.{.{ .name = "IM", .module = engine_module }},
        });
        try names.append(b.allocator, name);
        try modules.append(b.allocator, module);

        //nothing calls a file's functions in a check, and the compiler skips what isn't called, so its root asks for
        //every one by name
        const root_file = roots.add(b.fmt("{s}_check.zig", .{name}),
            \\const file = @import("file");
            \\comptime {
            \\    @setEvalBranchQuota(100_000);
            \\    for (@typeInfo(file).@"struct".decl_names) |name| _ = &@field(file, name);
            \\}
            \\
        );
        check_step.dependOn(&b.addObject(.{
            .name = name,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .root_source_file = root_file,
                .imports = &.{.{ .name = "file", .module = module }},
            }),
        }).step);
    }

    for (names.items, modules.items) |name, named_module| {
        if (ScriptImports.IsNotProjectFile(name)) continue;
        for (modules.items) |other| other.addImport(name, named_module);
    }

    const game_name = (try FindProjectFileName(b)) orelse {
        game_step.dependOn(&b.addFail("no .imprj file at the top of the project's folder, so there's no game to build").step);
        return;
    };
    const walk = WalkGame(b, game_step, engine, project, game_name) orelse return;
    const game: GameBuild = .{
        .mBuild = b,
        .mStep = game_step,
        .mRoots = roots,
        .mTarget = target,
        .mOptimize = optimize,
        .mName = game_name,
        .mWalk = walk,
    };
    game.AddScripts(engine, project, &files);

    const exe = b.addExecutable(.{
        .name = "ImaginGame",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = engine.path("src/Game.zig"),
            .imports = &.{.{ .name = "IM", .module = engine.module("ImaginEngionEngine") }},
        }),
    });
    game_step.dependOn(&b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = game_name } },
        .pdb_dir = .disabled,
    }).step);

    game.AddProjectFiles();
    game.AddEngineFiles(engine);

    //every path the game reads is from the folder it runs in, which is what this file is for
    const start_file = b.addWriteFiles().add("start.bat", b.fmt(
        "@echo off\r\ncd /d \"%~dp0\"\r\nImaginGame.exe \"{s}\\{s}.imprj\"\r\nif errorlevel 1 pause\r\n",
        .{ game_name, game_name },
    ));
    game_step.dependOn(&b.addInstallFileWithDir(start_file, .{ .custom = game_name }, b.fmt("{s}.bat", .{game_name})).step);

    game.AddReport(engine, project);

    const run = b.addRunArtifact(exe);
    run.setCwd(b.graph.path(.install_prefix, game_name));
    run.addArg(b.fmt("{s}/{s}.imprj", .{ game_name, game_name }));
    run.step.dependOn(game_step);
    run_step.dependOn(&run.step);
}

/// The name, without its extension, of the .imprj at the top of the project's folder. Null if it has none
fn FindProjectFileName(b: *std.Build) !?[]const u8 {
    var dir = try b.root.root_dir.handle.openDir(b.graph.io, ".", .{ .iterate = true });
    defer dir.close(b.graph.io);
    var iter = dir.iterate();
    while (try iter.next(b.graph.io)) |entry| {
        if (entry.kind == .file and std.mem.eql(u8, std.fs.path.extension(entry.name), ".imprj")) {
            return b.dupe(std.fs.path.stem(entry.name));
        }
    }
    return null;
}

/// Which files the game `game_name` needs. Null, with a failing step added to `game_step` saying why, for a project file
/// that can't be read. The build is set to run this again when a file it read changes, or any project folder gets a file
/// added or removed (AddProjectSteps does the project's folders)
fn WalkGame(b: *std.Build, game_step: *std.Build.Step, engine: *std.Build.Dependency, project: []const u8, game_name: []const u8) ?ProjectWalk.Result {
    const project_file = b.fmt("{s}.imprj", .{game_name});
    b.dependOnFileContents(b.path(project_file));

    const engine_path = engine.builder.root.root_dir.handle.realPathFileAlloc(b.graph.io, ".", b.allocator) catch |err| {
        game_step.dependOn(&b.addFail(b.fmt("couldn't find the engine's folder: {s}", .{@errorName(err)})).step);
        return null;
    };
    const walk = ProjectWalk.WalkProject(b.allocator, b.graph.io, project, engine_path, project_file) catch |err| {
        game_step.dependOn(&b.addFail(b.fmt("couldn't read {s}: {s}", .{ project_file, @errorName(err) })).step);
        return null;
    };

    for (walk.mRead.items) |file| {
        const root = if (file.mRoot == .Prj) project else engine_path;
        b.dependOnFileContents(.{ .cwd_relative = b.pathJoin(&.{ root, file.mPath }) });
    }
    b.dependOnDirectoryContents(engine.path(EngineFiles.ASSETS_PATH ++ "/" ++ EngineFiles.STOCK_SCRIPTS_FOLDER));
    return walk;
}

/// Fills zig-out/<name>/ with what the game needs, laid out the way the game reads it from the folder it runs in: the same
/// paths as in the engine's folder, and the project in a folder of its own
const GameBuild = struct {
    mBuild: *std.Build,
    mStep: *std.Build.Step,
    mRoots: *std.Build.Step.WriteFile,
    mTarget: std.Build.ResolvedTarget,
    mOptimize: std.builtin.OptimizeMode,
    mName: []const u8,
    mWalk: ProjectWalk.Result,

    /// Compiles the scripts the game loads into its exe: the engine gets a table of them ("game_scripts", which
    /// StaticScriptAsset reads) and they use the same engine module as the exe, so the game has one copy of the engine.
    /// Modules can import each other in a circle, so the engine importing the table that imports the engine is fine
    fn AddScripts(self: GameBuild, engine: *std.Build.Dependency, project: []const u8, files: *const ScriptImports.ProjectFiles) void {
        const b = self.mBuild;
        const engine_module = engine.module("ImaginEngionEngine");

        //every project file is a module under its name, which any of them can import, the same as the check step. Only
        //what the table reaches gets compiled
        var by_path: std.StringHashMapUnmanaged(*std.Build.Module) = .empty;
        var modules: std.ArrayList(*std.Build.Module) = .empty;
        var iter = files.mByName.iterator();
        while (iter.next()) |file| {
            const rel_path = file.value_ptr.*[project.len + 1 ..];
            const module = self.ScriptModule(engine_module, b.path(rel_path));
            modules.append(b.allocator, module) catch @panic("OOM");
            by_path.put(b.allocator, ProjectWalk.Normalize(b.allocator, rel_path) catch @panic("OOM"), module) catch @panic("OOM");
        }
        iter = files.mByName.iterator();
        var index: usize = 0;
        while (iter.next()) |file| : (index += 1) {
            if (ScriptImports.IsNotProjectFile(file.key_ptr.*)) continue;
            for (modules.items) |other| other.addImport(file.key_ptr.*, modules.items[index]);
        }

        //where each script is with its ScriptInfo, the same one `zig build script` exports from a DLL, so everything after
        //finding it works the same as in the editor. One the walk found no file for is left out: it's reported as missing
        var source: std.ArrayList(u8) = .empty;
        var imports: std.ArrayList(std.Build.Module.Import) = .empty;
        imports.append(b.allocator, .{ .name = "IM", .module = engine_module }) catch @panic("OOM");
        source.appendSlice(b.allocator,
            \\const IM = @import("IM");
            \\const Script = struct { mPath: []const u8, mInfo: *const IM.ScriptABI.ScriptInfo };
            \\pub const scripts = [_]Script{
            \\
        ) catch @panic("OOM");
        for (std.enums.values(ProjectWalk.FileRoot)) |root| {
            for (self.mWalk.mLoadedScripts.getPtrConst(root).keys()) |path| {
                const module = switch (root) {
                    .Prj => by_path.get(path) orelse continue,
                    .Eng => if (self.mWalk.mCode.getPtrConst(.Eng).contains(path)) self.ScriptModule(engine_module, engine.path(path)) else continue,
                };
                //by number: a project's script can have the same name as a stock one
                const import_name = b.fmt("script_{d}", .{imports.items.len});
                imports.append(b.allocator, .{ .name = import_name, .module = module }) catch @panic("OOM");
                source.print(b.allocator, "    .{{ .mPath = \"{f}\", .mInfo = &IM.ScriptExport.Exports(@import(\"{s}\"), \"{f}\", &.{{}}).info }},\n", .{
                    std.zig.fmtString(path),
                    import_name,
                    std.zig.fmtString(std.fs.path.stem(path)),
                }) catch @panic("OOM");
            }
        }
        source.appendSlice(b.allocator, "};\n") catch @panic("OOM");

        engine_module.addImport("game_scripts", b.createModule(.{
            .target = self.mTarget,
            .optimize = self.mOptimize,
            .root_source_file = self.mRoots.add("game_scripts.zig", source.items),
            .imports = imports.items,
        }));
    }

    fn ScriptModule(self: GameBuild, engine_module: *std.Build.Module, root: std.Build.LazyPath) *std.Build.Module {
        return self.mBuild.createModule(.{
            .target = self.mTarget,
            .optimize = self.mOptimize,
            .root_source_file = root,
            .imports = &.{.{ .name = "IM", .module = engine_module }},
        });
    }

    /// The project's files the game needs
    fn AddProjectFiles(self: GameBuild) void {
        const b = self.mBuild;
        const destination: std.Build.InstallDir = .{ .custom = b.fmt("{s}/{s}", .{ self.mName, self.mName }) };
        for (self.mWalk.mProject.keys()) |path| {
            self.mStep.dependOn(&b.addInstallFileWithDir(b.path(path), destination, path).step);
        }
    }

    /// The engine's files the game needs
    fn AddEngineFiles(self: GameBuild, engine: *std.Build.Dependency) void {
        const b = self.mBuild;
        const destination: std.Build.InstallDir = .{ .custom = self.mName };
        for (self.mWalk.mEngine.keys()) |path| {
            self.mStep.dependOn(&b.addInstallFileWithDir(engine.path(path), destination, path).step);
        }
    }

    /// Prints which of the game's files it needs and clears what earlier builds left (src/GameReport.zig) every time it's
    /// built, once everything added to the step so far is done so it's the last thing shown. It's compiled for the machine
    /// building, whatever the game's for
    fn AddReport(self: GameBuild, engine: *std.Build.Dependency, project: []const u8) void {
        const b = self.mBuild;
        const tool = b.addExecutable(.{
            .name = "GameReport",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = .Debug,
                .root_source_file = engine.path("src/GameReport.zig"),
            }),
        });
        const report = b.addRunArtifact(tool);
        report.stdio = .inherit;
        report.addArg(project);
        report.addDirectoryArg(engine.path("."));
        report.addArg(self.mName);
        report.addDirectoryArg(b.graph.path(.install_prefix, self.mName));
        if (b.option(bool, "trees", "Also print every object file's objects after building the game") orelse false) report.addArg("trees");

        for (self.mStep.dependencies.items) |step| report.step.dependOn(step);
        self.mStep.dependOn(&report.step);
    }
};

/// Whether two project files have one name, with a failing step added to `step` saying so
fn FailOnDuplicate(b: *std.Build, step: *std.Build.Step, files: *const ScriptImports.ProjectFiles) bool {
    const duplicate = files.mDuplicate orelse return false;
    step.dependOn(&b.addFail(b.fmt(
        "two files in the project are named {s}.zig: {s} and {s}. A project file is imported by its name, so each has to have its own",
        .{ duplicate.Name, duplicate.First, duplicate.Second },
    )).step);
    return true;
}

/// The project files the script at `path` imports, read from its text and theirs. Null, with a failing step added to
/// `script_step` saying why, for two project files with the same name or a name no project file has. The build is set
/// to run this again when any of the files read changes, or any project folder gets a file added or removed
fn FindImports(b: *std.Build, script_step: *std.Build.Step, path: []const u8, project: []const u8) !?ScriptImports.Collected {
    const io = b.graph.io;
    const files = try ScriptImports.FindProjectFiles(b.allocator, io, project);
    for (files.mFolders.items) |folder| b.dependOnDirectoryContents(.{ .cwd_relative = folder });

    if (FailOnDuplicate(b, script_step, &files)) return null;

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
