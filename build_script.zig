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

/// What a game project's build.zig calls (Project.WriteBuildFiles writes it), run from the project's folder:
/// - `zig build check`: every .zig file in the project compiles. It's what ZLS knows the files' imports from, which it
///   only reads from a compile step in the build.zig above a file
/// - `zig build game`, or just `zig build`: the game in zig-out/<name>/, a folder that runs with no zig or engine source
/// - `zig build rungame`: builds the game and runs it
pub fn ProjectBuild(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    //a project's build is for playing unless asked for something else. Scripts and the game have to match (see
    //WindowsScriptAsset.Build), which they do by all being built here
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Build mode, fast if not given") orelse .fast;
    const engine = b.dependency("GameEngine", .{ .target = target, .optimize = optimize, .@"prebuilt-scripts" = true });

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
    const game: GameBuild = .{
        .mBuild = b,
        .mStep = game_step,
        .mRoots = roots,
        .mTarget = target,
        .mOptimize = optimize,
        .mName = game_name,
    };

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

    for (names.items, modules.items) |name, module| game.AddScript(name, module);
    try game.AddProjectFiles();
    if (try game.AddEngineAssets(engine, engine_module, &files)) return;

    //every path the game reads is from the folder it runs in, which is what this file is for
    const start_file = b.addWriteFiles().add("start.bat", b.fmt(
        "@echo off\r\ncd /d \"%~dp0\"\r\nImaginGame.exe \"{s}\\{s}.imprj\"\r\nif errorlevel 1 pause\r\n",
        .{ game_name, game_name },
    ));
    game_step.dependOn(&b.addInstallFileWithDir(start_file, .{ .custom = game_name }, b.fmt("{s}.bat", .{game_name})).step);

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

/// The engine files a game can need when it runs: the default theme, what it points at, what an asset falls back on.
/// Fixed for now: nothing yet looks at what a game uses
const ENGINE_ASSETS = [_][]const u8{
    "fonts/default/static/ChironGoRoundTC-Bold.json",
    "fonts/default/static/ChironGoRoundTC-Bold.png",
    "fonts/default/static/ChironGoRoundTC-Bold.ttf",
    "fonts/default/static/ChironGoRoundTC-Regular.json",
    "fonts/default/static/ChironGoRoundTC-Regular.png",
    "fonts/default/static/ChironGoRoundTC-Regular.ttf",
    "sounds/DefaultSound.mp3",
    "textures/DefaultTexture.png",
    "textures/White.png",
    "themes/Default.imtheme",
};
const ENGINE_ASSETS_PATH = "src/Imaginengion/EngineAssets";
const STOCK_SCRIPTS_FOLDER = "scripts/UI";

/// Fills zig-out/<name>/, laid out the way the game reads it from the folder it runs in: the same paths as in the
/// engine's folder, and the project in a folder of its own
const GameBuild = struct {
    mBuild: *std.Build,
    mStep: *std.Build.Step,
    mRoots: *std.Build.Step.WriteFile,
    mTarget: std.Build.ResolvedTarget,
    mOptimize: std.builtin.OptimizeMode,
    mName: []const u8,

    /// `module`'s DLL, where WindowsScriptAsset.Open loads it from. A project also holds files that aren't scripts (its
    /// events, its enums), which can't be told from a script until they're compiled: those come out with nothing in them
    fn AddScript(self: GameBuild, name: []const u8, module: *std.Build.Module) void {
        const b = self.mBuild;
        const root_file = self.mRoots.add(b.fmt("{s}_game.zig", .{name}), b.fmt(
            \\const IM = @import("IM");
            \\const file = @import("file");
            \\fn GetInfo() callconv(.c) *const IM.ScriptABI.ScriptInfo {{
            \\    return &IM.ScriptExport.Exports(file, "{s}", &.{{}}).info;
            \\}}
            \\comptime {{
            \\    if (IM.ScriptExport.IsScript(file)) @export(&GetInfo, .{{ .name = IM.ScriptABI.INFO_SYMBOL }});
            \\}}
            \\
        , .{name}));
        const dll = b.addLibrary(.{
            .linkage = .dynamic,
            .name = b.fmt("{s}.zig", .{name}),
            .root_module = b.createModule(.{
                .target = self.mTarget,
                .optimize = self.mOptimize,
                .root_source_file = root_file,
                .imports = &.{
                    .{ .name = "IM", .module = module.import_table.get("IM").? },
                    .{ .name = "file", .module = module },
                },
            }),
        });
        self.mStep.dependOn(&b.addInstallArtifact(dll, .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("{s}/zig-out/bin", .{self.mName}) } },
            .pdb_dir = .disabled,
            .implib_dir = .disabled,
        }).step);
    }

    /// Everything in the project's folder but what's only for building it. Script files go too: the engine still opens
    /// the file when it loads a script's DLL
    fn AddProjectFiles(self: GameBuild) !void {
        const b = self.mBuild;
        const destination: std.Build.InstallDir = .{ .custom = b.fmt("{s}/{s}", .{ self.mName, self.mName }) };
        var dir = try b.root.root_dir.handle.openDir(b.graph.io, ".", .{ .iterate = true });
        defer dir.close(b.graph.io);
        var iter = dir.iterate();
        while (try iter.next(b.graph.io)) |entry| {
            const name = b.dupe(entry.name);
            switch (entry.kind) {
                .directory => {
                    if (ScriptImports.SkipFolder(name)) continue;
                    self.mStep.dependOn(&b.addInstallDirectory(.{
                        .source_dir = b.path(name),
                        .install_dir = destination,
                        .install_subdir = name,
                    }).step);
                },
                .file => {
                    if (name[0] == '.' or std.mem.eql(u8, name, "build.zig") or std.mem.eql(u8, name, "build.zig.zon")) continue;
                    self.mStep.dependOn(&b.addInstallFileWithDir(b.path(name), destination, name).step);
                },
                else => {},
            }
        }
    }

    /// ENGINE_ASSETS and the stock UI scripts with their DLLs. True, with a failing step added saying why, if a project
    /// file has a stock script's name: a DLL is named after its file, so one would be written over the other
    fn AddEngineAssets(self: GameBuild, engine: *std.Build.Dependency, engine_module: *std.Build.Module, project_files: *const ScriptImports.ProjectFiles) !bool {
        const b = self.mBuild;
        const destination: std.Build.InstallDir = .{ .custom = b.fmt("{s}/{s}", .{ self.mName, ENGINE_ASSETS_PATH }) };
        for (ENGINE_ASSETS) |asset| {
            self.mStep.dependOn(&b.addInstallFileWithDir(engine.path(b.fmt("{s}/{s}", .{ ENGINE_ASSETS_PATH, asset })), destination, asset).step);
        }
        self.mStep.dependOn(&b.addInstallDirectory(.{
            .source_dir = engine.path(ENGINE_ASSETS_PATH ++ "/" ++ STOCK_SCRIPTS_FOLDER),
            .install_dir = destination,
            .install_subdir = STOCK_SCRIPTS_FOLDER,
        }).step);

        const stock_folder = ENGINE_ASSETS_PATH ++ "/" ++ STOCK_SCRIPTS_FOLDER;
        const stock_path = try engine.builder.root.root_dir.handle.realPathFileAlloc(b.graph.io, stock_folder, b.allocator);
        const stock = try ScriptImports.FindProjectFiles(b.allocator, b.graph.io, stock_path);
        var iter = stock.mByName.iterator();
        while (iter.next()) |file| {
            const name = file.key_ptr.*;
            if (project_files.mByName.get(name)) |project_file| {
                self.mStep.dependOn(&b.addFail(b.fmt("{s} has the same name as the engine's stock script {s}.zig, and a game needs both: rename it", .{ project_file, name })).step);
                return true;
            }
            self.AddScript(name, b.createModule(.{
                .target = self.mTarget,
                .optimize = self.mOptimize,
                .root_source_file = engine.path(b.fmt("{s}/{s}", .{ stock_folder, file.value_ptr.*[stock_path.len + 1 ..] })),
                .imports = &.{.{ .name = "IM", .module = engine_module }},
            }));
        }
        return false;
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
