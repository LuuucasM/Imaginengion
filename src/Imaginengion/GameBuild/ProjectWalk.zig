//! Working out which files a game needs, starting from its project file and following what each file names: the entries,
//! every {"Path", "PathType"} saved in an object or theme file (components, scripts, script variables), a font's atlas next
//! to it, and the project files a script imports. Paths written inside a script's code aren't looked for: a script names
//! another file with a variable (IM.SceneRef and its siblings), which is saved like any other reference.
//! Only std: src/GameReport.zig, which the build compiles and runs, is built from this alone.
const std = @import("std");
const EngineFiles = @import("EngineFiles.zig");
const ScriptImports = @import("../Scripts/ScriptImports.zig");

const FileSet = std.StringArrayHashMapUnmanaged(void);

pub const SETTINGS_FOLDER = "ProjectSettings";

/// Which folder a saved path is from, the saved names of AManager.PathType's values that have files
pub const FileRoot = enum { Prj, Eng };

pub const Missing = struct {
    mRoot: FileRoot,
    mPath: []const u8,
    /// the file that names it
    mFrom: []const u8,
};

pub const Unreadable = struct {
    mPath: []const u8,
    mReason: []const u8,
};

pub const Result = struct {
    /// the project's needed files, as paths from its folder with / between folders
    mProject: FileSet = .empty,
    /// the engine's needed files, as paths from its folder with / between folders
    mEngine: FileSet = .empty,
    mMissing: std.ArrayList(Missing) = .empty,
    /// object and theme files that are there but aren't JSON, so what they name is unknown
    mUnreadable: std.ArrayList(Unreadable) = .empty,
    /// the project file's fields for the entries that aren't set
    mUnsetEntries: std.ArrayList([]const u8) = .empty,
};

/// What building a game copies but the game doesn't need, sorted
pub const NotNeeded = struct {
    mProject: std.ArrayList([]const u8) = .empty,
    mEngine: std.ArrayList([]const u8) = .empty,
};

/// The fields of a project file (Project.ProjectFile) that name a file
const ProjectFile = struct {
    WindowIcon: []const u8 = "",
    EntryScene: []const u8 = "",
    EntryPlayer: []const u8 = "",
    EntryGameContext: []const u8 = "",
};

/// A file at the top of a project's folder that's only for building it, and so never goes into its game
pub fn IsBuildOnlyFile(name: []const u8) bool {
    return name.len == 0 or name[0] == '.' or std.mem.eql(u8, name, "build.zig") or std.mem.eql(u8, name, "build.zig.zon");
}

/// Everything the game whose project file is `project_file_name` in `project_path` needs, with `engine_path` the engine's
/// folder. An error only for a project file that can't be read: anything else wrong is in what it returns. Memory from
/// `arena`
pub fn WalkProject(arena: std.mem.Allocator, io: std.Io, project_path: []const u8, engine_path: []const u8, project_file_name: []const u8) !Result {
    const resolved_project = try std.fs.path.resolveAlloc(arena, &.{project_path});
    var walker: Walker = .{
        .mArena = arena,
        .mIo = io,
        .mProjectPath = resolved_project,
        .mEnginePath = engine_path,
        .mProjectFiles = try ScriptImports.FindProjectFiles(arena, io, resolved_project),
    };

    try walker.AddProjectFile(project_file_name);
    try walker.AddSettings(project_file_name);
    for (EngineFiles.ALWAYS_NEEDED) |path| try walker.Add(.Eng, path, "the engine");

    while (walker.mToRead.pop()) |file| try walker.Read(file);
    return walker.mResult;
}

const ToRead = struct {
    mRoot: FileRoot,
    mPath: []const u8,
};

const Walker = struct {
    mArena: std.mem.Allocator,
    mIo: std.Io,
    mProjectPath: []const u8,
    mEnginePath: []const u8,
    mProjectFiles: ScriptImports.ProjectFiles,
    mResult: Result = .{},
    /// every file named so far, needed or missing, so each is only looked at once
    mSeen: FileSet = .empty,
    mToRead: std.ArrayList(ToRead) = .empty,

    fn AddProjectFile(self: *Walker, name: []const u8) !void {
        const contents = try std.Io.Dir.cwd().readFileAlloc(self.mIo, try self.FullPath(.Prj, name), self.mArena, .unlimited);
        const project_file = try std.json.parseFromSliceLeaky(ProjectFile, self.mArena, contents, .{ .ignore_unknown_fields = true });
        try self.mResult.mProject.put(self.mArena, name, {});

        inline for (.{ "EntryScene", "EntryPlayer", "EntryGameContext" }) |field| {
            const path = @field(project_file, field);
            if (path.len == 0) {
                try self.mResult.mUnsetEntries.append(self.mArena, field);
            } else {
                try self.Add(.Prj, path, name);
            }
        }
        if (project_file.WindowIcon.len > 0) try self.Add(.Prj, project_file.WindowIcon, name);
    }

    /// The files of the settings folder: the engine opens each one with the project, and nothing names them
    fn AddSettings(self: *Walker, project_file_name: []const u8) !void {
        var dir = std.Io.Dir.cwd().openDir(self.mIo, try self.FullPath(.Prj, SETTINGS_FOLDER), .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return,
            else => |e| return e,
        };
        defer dir.close(self.mIo);
        var iter = dir.iterate();
        while (try iter.next(self.mIo)) |entry| {
            if (entry.kind != .file) continue;
            try self.Add(.Prj, try std.fmt.allocPrint(self.mArena, "{s}/{s}", .{ SETTINGS_FOLDER, entry.name }), project_file_name);
        }
    }

    /// `path` is needed because `from` names it
    fn Add(self: *Walker, root: FileRoot, path: []const u8, from: []const u8) !void {
        const normalized = try self.mArena.dupe(u8, path);
        std.mem.replaceScalar(u8, normalized, '\\', '/');

        const seen = try self.mSeen.getOrPut(self.mArena, try std.fmt.allocPrint(self.mArena, "{s}:{s}", .{ @tagName(root), normalized }));
        if (seen.found_existing) return;

        std.Io.Dir.cwd().access(self.mIo, try self.FullPath(root, normalized), .{}) catch {
            try self.mResult.mMissing.append(self.mArena, .{ .mRoot = root, .mPath = normalized, .mFrom = from });
            return;
        };

        const set = if (root == .Prj) &self.mResult.mProject else &self.mResult.mEngine;
        try set.put(self.mArena, normalized, {});
        try self.mToRead.append(self.mArena, .{ .mRoot = root, .mPath = normalized });
    }

    fn FullPath(self: *Walker, root: FileRoot, path: []const u8) ![]const u8 {
        return try std.fs.path.join(self.mArena, &.{ if (root == .Prj) self.mProjectPath else self.mEnginePath, path });
    }

    /// Adds what `file` names, which depends on the kind of file it is. A file of any other kind names nothing
    fn Read(self: *Walker, file: ToRead) !void {
        const extension = std.fs.path.extension(file.mPath);
        if (HasExtension(extension, &.{ ".ttf", ".otf" })) {
            //its atlas: TextAsset opens these next to the font
            const base = file.mPath[0 .. file.mPath.len - extension.len];
            try self.Add(file.mRoot, try std.fmt.allocPrint(self.mArena, "{s}.json", .{base}), file.mPath);
            try self.Add(file.mRoot, try std.fmt.allocPrint(self.mArena, "{s}.png", .{base}), file.mPath);
        } else if (HasExtension(extension, &.{".zig"})) {
            //an engine script is built with no project files to import
            if (file.mRoot == .Prj) try self.FollowImports(file.mPath);
        } else if (HasExtension(extension, &.{ ".imsc", ".impl", ".imgc", ".imen" }) or IsSetting(file)) {
            try self.ScanJsonFile(file, null);
        } else if (HasExtension(extension, &.{".imtheme"})) {
            //a theme's font doesn't have to say where it's from (ThemeAsset.FileFont)
            try self.ScanJsonFile(file, .Eng);
        }
    }

    fn FollowImports(self: *Walker, path: []const u8) !void {
        const script = try self.FullPath(.Prj, path);
        const resolved_script = try std.fs.path.resolveAlloc(self.mArena, &.{script});
        const collected = try ScriptImports.Collect(self.mArena, self.mIo, resolved_script, &self.mProjectFiles);
        for (collected.mDependencies.items) |dependency| {
            if (!std.mem.startsWith(u8, dependency, self.mProjectPath)) continue;
            try self.Add(.Prj, dependency[self.mProjectPath.len + 1 ..], path);
        }
        if (collected.mMissing) |missing| {
            const name = try std.fmt.allocPrint(self.mArena, "{s}.zig", .{missing.Name});
            const from = try self.mArena.dupe(u8, missing.In[self.mProjectPath.len + 1 ..]);
            std.mem.replaceScalar(u8, from, '\\', '/');
            try self.Add(.Prj, name, from);
        }
    }

    fn ScanJsonFile(self: *Walker, file: ToRead, default_root: ?FileRoot) !void {
        const contents = std.Io.Dir.cwd().readFileAlloc(self.mIo, try self.FullPath(file.mRoot, file.mPath), self.mArena, .unlimited) catch |err| {
            return self.AddUnreadable(file.mPath, err);
        };
        const value = std.json.parseFromSliceLeaky(std.json.Value, self.mArena, contents, .{}) catch |err| {
            return self.AddUnreadable(file.mPath, err);
        };
        try self.ScanValue(value, file.mPath, default_root);
    }

    fn AddUnreadable(self: *Walker, path: []const u8, err: anyerror) !void {
        try self.mResult.mUnreadable.append(self.mArena, .{ .mPath = path, .mReason = @errorName(err) });
    }

    fn ScanValue(self: *Walker, value: std.json.Value, from: []const u8, default_root: ?FileRoot) anyerror!void {
        switch (value) {
            .object => |object| {
                if (FileRefOf(object, default_root)) |ref| return try self.Add(ref.mRoot, ref.mPath, from);
                var iter = object.iterator();
                while (iter.next()) |entry| try self.ScanValue(entry.value_ptr.*, from, default_root);
            },
            .array => |array| for (array.items) |item| try self.ScanValue(item, from, default_root),
            else => {},
        }
    }
};

/// The file a saved JSON object is a reference to (AssetHandle.FileRef), null if it isn't one
fn FileRefOf(object: std.json.ObjectMap, default_root: ?FileRoot) ?ToRead {
    const path = object.get("Path") orelse return null;
    if (path != .string) return null;

    const root = if (object.get("PathType")) |path_type| blk: {
        if (path_type != .string) return null;
        break :blk std.meta.stringToEnum(FileRoot, path_type.string) orelse return null;
    } else default_root orelse return null;

    return .{ .mRoot = root, .mPath = path.string };
}

fn HasExtension(extension: []const u8, wanted: []const []const u8) bool {
    for (wanted) |want| {
        if (std.ascii.eqlIgnoreCase(extension, want)) return true;
    }
    return false;
}

fn IsSetting(file: ToRead) bool {
    return file.mRoot == .Prj and std.mem.startsWith(u8, file.mPath, SETTINGS_FOLDER ++ "/");
}

/// What `result` doesn't have of what build_script.zig's GameBuild copies into a game
pub fn FindNotNeeded(arena: std.mem.Allocator, io: std.Io, project_path: []const u8, engine_path: []const u8, result: *const Result) !NotNeeded {
    var not_needed: NotNeeded = .{};

    var project_dir = try std.Io.Dir.cwd().openDir(io, project_path, .{ .iterate = true });
    defer project_dir.close(io);
    var project_walker = try project_dir.walkSelectively(arena);
    defer project_walker.deinit();
    while (try project_walker.next(io)) |entry| {
        const at_top = std.mem.indexOfAny(u8, entry.path, "/\\") == null;
        switch (entry.kind) {
            .directory => {
                if (at_top and ScriptImports.SkipFolder(entry.basename)) continue;
                try project_walker.enter(io, entry);
            },
            .file => {
                if (at_top and IsBuildOnlyFile(entry.basename)) continue;
                const path = try arena.dupe(u8, entry.path);
                std.mem.replaceScalar(u8, path, '\\', '/');
                if (!result.mProject.contains(path)) try not_needed.mProject.append(arena, path);
            },
            else => {},
        }
    }

    for (EngineFiles.COPIED_ASSETS) |asset| {
        const path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ EngineFiles.ASSETS_PATH, asset });
        if (!result.mEngine.contains(path)) try not_needed.mEngine.append(arena, path);
    }

    const stock_folder = EngineFiles.ASSETS_PATH ++ "/" ++ EngineFiles.STOCK_SCRIPTS_FOLDER;
    var stock_dir = try std.Io.Dir.cwd().openDir(io, try std.fs.path.join(arena, &.{ engine_path, stock_folder }), .{ .iterate = true });
    defer stock_dir.close(io);
    var stock_walker = try stock_dir.walkSelectively(arena);
    defer stock_walker.deinit();
    while (try stock_walker.next(io)) |entry| {
        switch (entry.kind) {
            .directory => try stock_walker.enter(io, entry),
            .file => {
                const path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ stock_folder, entry.path });
                std.mem.replaceScalar(u8, path, '\\', '/');
                if (!result.mEngine.contains(path)) try not_needed.mEngine.append(arena, path);
            },
            else => {},
        }
    }

    std.mem.sort([]const u8, not_needed.mProject.items, {}, PathLessThan);
    std.mem.sort([]const u8, not_needed.mEngine.items, {}, PathLessThan);
    return not_needed;
}

fn PathLessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// What `zig build game` prints about a game
pub fn WriteReport(out: *std.Io.Writer, game_name: []const u8, result: *const Result, not_needed: *const NotNeeded) !void {
    try out.print("{s}: {d} files needed\n", .{ game_name, result.mProject.count() + result.mEngine.count() });
    try WriteCounts(out, "project", result.mProject.keys());
    try WriteCounts(out, "engine", result.mEngine.keys());

    const not_needed_count = not_needed.mProject.items.len + not_needed.mEngine.items.len;
    if (not_needed_count > 0) {
        try out.print("Not needed, still copied ({d}):\n", .{not_needed_count});
        for (not_needed.mProject.items) |path| try out.print("  {s}\n", .{path});
        for (not_needed.mEngine.items) |path| try out.print("  (engine) {s}\n", .{EngineRelative(path)});
    }

    const problem_count = result.mMissing.items.len + result.mUnreadable.items.len + result.mUnsetEntries.items.len;
    if (problem_count == 0) {
        try out.writeAll("Missing: none\n");
        return;
    }
    try out.print("Missing ({d}):\n", .{problem_count});
    for (result.mUnsetEntries.items) |field| try out.print("  {s} isn't set in the project file\n", .{field});
    for (result.mMissing.items) |missing| {
        const prefix = if (missing.mRoot == .Eng) "(engine) " else "";
        try out.print("  {s}{s}, named by {s}\n", .{ prefix, EngineRelative(missing.mPath), missing.mFrom });
    }
    for (result.mUnreadable.items) |unreadable| try out.print("  {s} can't be read: {s}\n", .{ unreadable.mPath, unreadable.mReason });
}

/// One line of the report: how many of `paths` there are, by kind of file
fn WriteCounts(out: *std.Io.Writer, label: []const u8, paths: []const []const u8) !void {
    var object_files: usize = 0;
    var scripts: usize = 0;
    var other: usize = 0;
    for (paths) |path| {
        const extension = std.fs.path.extension(path);
        if (HasExtension(extension, &.{ ".imsc", ".impl", ".imgc", ".imen" })) {
            object_files += 1;
        } else if (HasExtension(extension, &.{".zig"})) {
            scripts += 1;
        } else {
            other += 1;
        }
    }
    try out.print("  {s} {d}: object files {d}, scripts {d}, other {d}\n", .{ label, paths.len, object_files, scripts, other });
}

/// An engine path as the build's list of assets has it, from the engine's assets folder
fn EngineRelative(path: []const u8) []const u8 {
    const prefix = EngineFiles.ASSETS_PATH ++ "/";
    return if (std.mem.startsWith(u8, path, prefix)) path[prefix.len..] else path;
}
