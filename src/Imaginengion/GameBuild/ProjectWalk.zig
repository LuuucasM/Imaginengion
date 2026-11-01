//! Working out which files a game needs, starting from its project file and following what each file names: the entries,
//! every {"Path", "PathType"} saved in an object or theme file (components, scripts, script variables), a font's atlas next
//! to it, and the project files a script imports. Paths written inside a script's code aren't looked for: a script names
//! another file with a variable (IM.SceneRef and its siblings), which is saved like any other reference.
//! What comes out is a forest, not one tree: each object file gives a tree of objects, each script file what it declares,
//! and the links between files join them. A file can be named by many others, and files can name each other in a circle.
//! Passes read the forest and don't change it, see ForestChecks.zig. build_script.zig's GameBuild is one: a game gets the
//! files the forest needs and nothing else. A font is named but isn't needed itself: its atlas is what a game reads.
//! Only std: build_script.zig runs this, and src/GameReport.zig, which the build compiles and runs, is built from it.
const std = @import("std");
const Ast = std.zig.Ast;
const EngineFiles = @import("EngineFiles.zig");
const ScriptImports = @import("../Scripts/ScriptImports.zig");

const FileSet = std.StringArrayHashMapUnmanaged(void);

pub const SETTINGS_FOLDER = "ProjectSettings";

/// Which folder a saved path is from, the saved names of AManager.PathType's values that have files
pub const FileRoot = enum { Prj, Eng };

/// A file of the game, by a path from its root with / between folders
pub const FileId = struct {
    mRoot: FileRoot,
    mPath: []const u8,
};

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

/// One file naming another
pub const FileLink = struct {
    /// null for what the engine needs in every game, which no file names
    mFrom: ?FileId,
    mTo: FileId,
    /// what in mFrom names it, in words
    mVia: []const u8,
};

/// The type of an object saved in a file
pub const ObjectKind = enum { Scene, Entity, Player, GameContext };

/// What's known of an object with a UUID, from anywhere in the forest
pub const ObjectSymbol = struct {
    mFile: FileId,
    mKind: ObjectKind,
    mName: []const u8,
};

/// Something saved on an object that points at another object by its UUID
pub const ObjectLink = struct {
    /// a script variable's name, or a component's field as Overlay.Scene
    mField: []const u8,
    mUUID: u64,
    mWants: ObjectKind,
    /// null if no needed file has an object with that UUID
    mTarget: ?ObjectSymbol,
};

/// A script on an object
pub const ScriptUse = struct {
    mFile: FileId,
    /// its saved variables by name, null if it saved none
    mValues: ?std.json.ObjectMap = null,
    /// which of its variables point at other objects
    mLinks: std.ArrayList(ObjectLink) = .empty,
};

/// One object of an object file and everything saved under it
pub const ObjectNode = struct {
    mKind: ObjectKind,
    mName: []const u8 = "",
    mUUID: ?u64 = null,
    /// its components as saved, by their saved names, without UUIDComponent and NameComponent which every object has
    mComponents: std.StringArrayHashMapUnmanaged(std.json.Value) = .empty,
    /// which of its components point at other objects
    mLinks: std.ArrayList(ObjectLink) = .empty,
    mScripts: std.ArrayList(ScriptUse) = .empty,
    mChildren: std.ArrayList(ObjectNode) = .empty,
};

/// How many objects of one type there are, and what they hold
pub const KindCounts = struct {
    mObjects: usize = 0,
    mScripts: usize = 0,
    /// how many of the objects have each component, by its saved name, sorted by name
    mComponents: std.StringArrayHashMapUnmanaged(usize) = .empty,
};

pub const ObjectCounts = std.EnumArray(ObjectKind, KindCounts);

/// A scene, entity, player or game context file. Each is here once however many files name it, and a template's copies
/// only have what they save themselves: what they get from the template is in the template's own file
pub const ObjectFile = struct {
    mFile: FileId,
    mObject: ObjectNode,
    mCounts: ObjectCounts,
};

/// A variable a script declares
pub const Variable = struct {
    mName: []const u8,
    /// its type as the script writes it
    mType: []const u8,
    /// the type of object it holds, saved as a UUID, if it's an object variable
    mObject: ?ObjectKind = null,
    /// the type of object its file holds, if it's a file ref variable
    mFileRef: ?ObjectKind = null,
};

/// What a .zig file declares, read from its code. A project's events, enums and helpers are these too, with no owner
pub const ScriptFile = struct {
    /// the object type its hooks and event handlers take, null for a file with none, which isn't a script
    mOwner: ?ObjectKind = null,
    mVariables: std.ArrayList(Variable) = .empty,
    /// the names of its hooks and event handlers
    mFunctions: std.ArrayList([]const u8) = .empty,
    mSyntaxErrors: usize = 0,
    /// whether its code names IM.Widgets, whose builders put stock scripts on what they make
    mUsesWidgets: bool = false,

    pub fn GetVariable(self: *const ScriptFile, name: []const u8) ?*const Variable {
        for (self.mVariables.items) |*variable| {
            if (std.mem.eql(u8, variable.mName, name)) return variable;
        }
        return null;
    }
};

/// By path, sorted
pub const ScriptFiles = std.StringArrayHashMapUnmanaged(ScriptFile);

pub const Result = struct {
    /// the project's needed files, as paths from its folder with / between folders
    mProject: FileSet = .empty,
    /// the engine's needed files, as paths from its folder with / between folders
    mEngine: FileSet = .empty,
    /// sorted by path
    mObjectFiles: std.ArrayList(ObjectFile) = .empty,
    /// mObjectFiles' counts added up
    mObjectTotals: ObjectCounts = .initFill(.{}),
    mScriptFiles: std.EnumArray(FileRoot, ScriptFiles) = .initFill(.empty),
    /// the scripts the game loads, so compiles into its exe. What a script only imports comes along with it
    mLoadedScripts: std.EnumArray(FileRoot, FileSet) = .initFill(.empty),
    /// the fonts named that the game gets as their atlas instead of the font itself, sorted. One whose atlas isn't all
    /// there isn't one: it's in mMissing
    mFonts: std.EnumArray(FileRoot, FileSet) = .initFill(.empty),
    /// every file the walk read: what's above can only change when one of these does, or a folder gets a file added or
    /// removed
    mRead: std.ArrayList(FileId) = .empty,
    /// every link between files, those from one file together, sorted by that file
    mFileLinks: std.ArrayList(FileLink) = .empty,
    /// every saved object with a UUID, by that UUID
    mSymbols: std.AutoHashMapUnmanaged(u64, ObjectSymbol) = .empty,
    mMissing: std.ArrayList(Missing) = .empty,
    /// object and theme files that are there but aren't JSON, so what they name is unknown
    mUnreadable: std.ArrayList(Unreadable) = .empty,
    /// the project file's fields for the entries that aren't set
    mUnsetEntries: std.ArrayList([]const u8) = .empty,
};

/// What a game leaves out of the project's files and the engine's stock scripts because nothing uses them, sorted
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

/// The components that save a UUID pointing at another object in the forest. The saved files don't say which fields are
/// UUIDs, so this has to be kept up by hand. AudioComponent's Bus is left out: buses aren't in the forest
const COMPONENT_LINKS = [_]struct { mComponent: []const u8, mField: []const u8, mWants: ObjectKind }{
    .{ .mComponent = "OverlayComponent", .mField = "Scene", .mWants = .Scene },
    .{ .mComponent = "SpawnPossComponent", .mField = "EntityRef", .mWants = .Entity },
    .{ .mComponent = "PopupRefComponent", .mField = "Popup", .mWants = .Entity },
};

/// Whether `path` is a font, which the editor makes an atlas from
pub fn IsFontFile(path: []const u8) bool {
    return HasExtension(std.fs.path.extension(path), &.{ ".ttf", ".otf" });
}

/// The .json of the atlas of the font at `path`, which sits next to it. Its .png is named the same way
pub fn AtlasJsonOf(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}.json", .{path[0 .. path.len - std.fs.path.extension(path).len]});
}

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
    for (EngineFiles.ALWAYS_NEEDED) |path| try walker.Add(.Eng, path, null, "every game needs it");

    while (walker.mToRead.pop()) |file| try walker.Read(file);

    const result = &walker.mResult;
    std.mem.sort(ObjectFile, result.mObjectFiles.items, {}, ObjectFileLessThan);
    std.mem.sort(FileLink, result.mFileLinks.items, {}, FileLinkLessThan);
    for (&result.mScriptFiles.values) |*scripts| SortByName(scripts);
    for (&result.mFonts.values) |*fonts| SortByName(fonts);

    //what a link points at can be in a file read after it, so links are found once every file has been read
    for (result.mObjectFiles.items) |*file| try AddSymbols(arena, result, file.mFile, &file.mObject);
    for (result.mObjectFiles.items) |*file| {
        try BindLinks(arena, result, &file.mObject);
        try AddCounts(arena, &result.mObjectTotals, &file.mObject);
        SortCounts(&file.mCounts);
    }
    SortCounts(&result.mObjectTotals);
    return result.*;
}

const Walker = struct {
    mArena: std.mem.Allocator,
    mIo: std.Io,
    mProjectPath: []const u8,
    mEnginePath: []const u8,
    mProjectFiles: ScriptImports.ProjectFiles,
    mResult: Result = .{},
    /// every file named so far, needed or missing, so each is only looked at once
    mSeen: FileSet = .empty,
    mToRead: std.ArrayList(FileId) = .empty,

    fn AddProjectFile(self: *Walker, name: []const u8) !void {
        const from: FileId = .{ .mRoot = .Prj, .mPath = name };
        try self.mResult.mRead.append(self.mArena, from);
        const contents = try std.Io.Dir.cwd().readFileAlloc(self.mIo, try self.FullPath(.Prj, name), self.mArena, .unlimited);
        const project_file = try std.json.parseFromSliceLeaky(ProjectFile, self.mArena, contents, .{ .ignore_unknown_fields = true });
        try self.mResult.mProject.put(self.mArena, name, {});

        inline for (.{ "EntryScene", "EntryPlayer", "EntryGameContext" }) |field| {
            const path = @field(project_file, field);
            if (path.len == 0) {
                try self.mResult.mUnsetEntries.append(self.mArena, field);
            } else {
                try self.Add(.Prj, path, from, field);
            }
        }
        if (project_file.WindowIcon.len > 0) try self.Add(.Prj, project_file.WindowIcon, from, "WindowIcon");
    }

    /// The files of the settings folder: the engine opens each one with the project, and nothing names them
    fn AddSettings(self: *Walker, project_file_name: []const u8) !void {
        var dir = std.Io.Dir.cwd().openDir(self.mIo, try self.FullPath(.Prj, SETTINGS_FOLDER), .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return,
            else => |e| return e,
        };
        defer dir.close(self.mIo);
        const from: FileId = .{ .mRoot = .Prj, .mPath = project_file_name };
        var iter = dir.iterate();
        while (try iter.next(self.mIo)) |entry| {
            if (entry.kind != .file) continue;
            try self.Add(.Prj, try std.fmt.allocPrint(self.mArena, "{s}/{s}", .{ SETTINGS_FOLDER, entry.name }), from, "settings folder");
        }
    }

    /// `path` is needed because of `via` in `from`
    fn Add(self: *Walker, root: FileRoot, path: []const u8, from: ?FileId, via: []const u8) !void {
        const normalized = try Normalize(self.mArena, path);
        try self.mResult.mFileLinks.append(self.mArena, .{ .mFrom = from, .mTo = .{ .mRoot = root, .mPath = normalized }, .mVia = via });

        const seen = try self.mSeen.getOrPut(self.mArena, try std.fmt.allocPrint(self.mArena, "{s}:{s}", .{ @tagName(root), normalized }));
        if (seen.found_existing) return;

        std.Io.Dir.cwd().access(self.mIo, try self.FullPath(root, normalized), .{}) catch {
            const named_by = if (from) |file| file.mPath else "the engine";
            try self.mResult.mMissing.append(self.mArena, .{ .mRoot = root, .mPath = normalized, .mFrom = named_by });
            return;
        };

        if (!IsFontFile(normalized)) {
            const set = if (root == .Prj) &self.mResult.mProject else &self.mResult.mEngine;
            try set.put(self.mArena, normalized, {});
        }
        try self.mToRead.append(self.mArena, .{ .mRoot = root, .mPath = normalized });
    }

    fn FullPath(self: *Walker, root: FileRoot, path: []const u8) ![]const u8 {
        return try std.fs.path.join(self.mArena, &.{ if (root == .Prj) self.mProjectPath else self.mEnginePath, path });
    }

    /// Adds what `file` holds to the forest and what it names to the files to read, which depends on the kind of file it
    /// is. A file of any other kind names nothing
    fn Read(self: *Walker, file: FileId) !void {
        const extension = std.fs.path.extension(file.mPath);
        if (IsFontFile(file.mPath)) {
            //its atlas: TextAsset opens these next to the font
            const base = file.mPath[0 .. file.mPath.len - extension.len];
            const json = try AtlasJsonOf(self.mArena, file.mPath);
            const png = try std.fmt.allocPrint(self.mArena, "{s}.png", .{base});
            try self.Add(file.mRoot, json, file, "font atlas");
            try self.Add(file.mRoot, png, file, "font atlas");

            const needed = if (file.mRoot == .Prj) &self.mResult.mProject else &self.mResult.mEngine;
            if (needed.contains(json) and needed.contains(png)) try self.mResult.mFonts.getPtr(file.mRoot).put(self.mArena, file.mPath, {});
        } else if (HasExtension(extension, &.{".zig"})) {
            try self.ReadCode(file);
        } else if (ObjectKindOf(extension)) |kind| {
            const value = try self.ReadJson(file) orelse return;
            if (value != .object) return self.AddUnreadable(file.mPath, error.NotAnObject);
            try self.AddObjectFile(file, value.object, kind);
        } else if (IsSetting(file)) {
            if (try self.ReadJson(file)) |value| try self.ScanValue(value, file, null, "settings");
        } else if (HasExtension(extension, &.{".imtheme"})) {
            //a theme's font doesn't have to say where it's from (ThemeAsset.FileFont)
            if (try self.ReadJson(file)) |value| try self.ScanValue(value, file, .Eng, "theme");
        }
    }

    fn ReadCode(self: *Walker, file: FileId) !void {
        try self.mResult.mRead.append(self.mArena, file);
        const source = std.Io.Dir.cwd().readFileAlloc(self.mIo, try self.FullPath(file.mRoot, file.mPath), self.mArena, .unlimited) catch |err| {
            return self.AddUnreadable(file.mPath, err);
        };
        const script = try ParseScript(self.mArena, source);
        try self.mResult.mScriptFiles.getPtr(file.mRoot).put(self.mArena, file.mPath, script);
        if (script.mUsesWidgets) try self.AddStockScripts(file);
        //an engine script is built with no project files to import
        if (file.mRoot == .Prj) try self.FollowImports(file, source);
    }

    /// Every stock script: which widget builders a file calls could be narrowed down to which scripts it needs, but that
    /// would be a table to keep up with Widgets by hand
    fn AddStockScripts(self: *Walker, file: FileId) !void {
        const folder = EngineFiles.ASSETS_PATH ++ "/" ++ EngineFiles.STOCK_SCRIPTS_FOLDER;
        var dir = try std.Io.Dir.cwd().openDir(self.mIo, try self.FullPath(.Eng, folder), .{ .iterate = true });
        defer dir.close(self.mIo);
        var iter = dir.iterate();
        while (try iter.next(self.mIo)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig")) continue;
            const path = try std.fmt.allocPrint(self.mArena, "{s}/{s}", .{ folder, entry.name });
            try self.Add(.Eng, path, file, "uses Widgets");
            try self.mResult.mLoadedScripts.getPtr(.Eng).put(self.mArena, path, {});
        }
    }

    fn FollowImports(self: *Walker, file: FileId, source: []const u8) !void {
        const imports = try ScriptImports.ImportsOf(self.mArena, source);
        for (imports.items) |import| {
            const found: []const u8 = switch (import) {
                .Name => |name| self.mProjectFiles.mByName.get(name) orelse {
                    try self.Add(.Prj, try std.fmt.allocPrint(self.mArena, "{s}.zig", .{name}), file, "import");
                    continue;
                },
                .Path => |rel_path| try std.fs.path.resolveAlloc(self.mArena, &.{ std.fs.path.dirname(try self.FullPath(.Prj, file.mPath)) orelse ".", rel_path }),
            };
            if (!std.mem.startsWith(u8, found, self.mProjectPath)) continue;
            try self.Add(.Prj, found[self.mProjectPath.len + 1 ..], file, "import");
        }
    }

    /// What's in `file`, null if that can't be read
    fn ReadJson(self: *Walker, file: FileId) !?std.json.Value {
        try self.mResult.mRead.append(self.mArena, file);
        const contents = std.Io.Dir.cwd().readFileAlloc(self.mIo, try self.FullPath(file.mRoot, file.mPath), self.mArena, .unlimited) catch |err| {
            try self.AddUnreadable(file.mPath, err);
            return null;
        };
        return std.json.parseFromSliceLeaky(std.json.Value, self.mArena, contents, .{}) catch |err| {
            try self.AddUnreadable(file.mPath, err);
            return null;
        };
    }

    fn AddUnreadable(self: *Walker, path: []const u8, err: anyerror) !void {
        try self.mResult.mUnreadable.append(self.mArena, .{ .mPath = path, .mReason = @errorName(err) });
    }

    /// Adds every file named anywhere in `value`
    fn ScanValue(self: *Walker, value: std.json.Value, from: FileId, default_root: ?FileRoot, via: []const u8) anyerror!void {
        switch (value) {
            .object => |object| {
                if (FileRefOf(object, default_root)) |ref| return try self.Add(ref.mRoot, ref.mPath, from, via);
                var iter = object.iterator();
                while (iter.next()) |entry| try self.ScanValue(entry.value_ptr.*, from, default_root, via);
            },
            .array => |array| for (array.items) |item| try self.ScanValue(item, from, default_root, via),
            else => {},
        }
    }

    fn AddObjectFile(self: *Walker, file: FileId, saved: std.json.ObjectMap, kind: ObjectKind) !void {
        const object = try self.BuildObject(file, saved, kind);
        var counts: ObjectCounts = .initFill(.{});
        try AddCounts(self.mArena, &counts, &object);
        try self.mResult.mObjectFiles.append(self.mArena, .{ .mFile = file, .mObject = object, .mCounts = counts });
    }

    /// `saved` as TextSerializer writes an object: its components, "Scripts", "Children" of its own type, and for a scene
    /// its "Entities"
    fn BuildObject(self: *Walker, file: FileId, saved: std.json.ObjectMap, kind: ObjectKind) anyerror!ObjectNode {
        var object: ObjectNode = .{ .mKind = kind };
        if (saved.get("NameComponent")) |name| object.mName = NameOf(name);
        if (saved.get("UUIDComponent")) |uuid| object.mUUID = SavedUUIDOf(uuid);

        var iter = saved.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            if (std.mem.eql(u8, key, "Scripts")) {
                try self.AddScripts(file, &object, value);
            } else if (std.mem.eql(u8, key, "Children")) {
                try self.AddChildren(file, &object, value, kind);
            } else if (std.mem.eql(u8, key, "Entities")) {
                try self.AddChildren(file, &object, value, .Entity);
            } else if (!std.mem.eql(u8, key, "NameComponent") and !std.mem.eql(u8, key, "UUIDComponent")) {
                try object.mComponents.put(self.mArena, key, value);
                try self.ScanValue(value, file, null, try std.fmt.allocPrint(self.mArena, "{s} on \"{s}\"", .{ ShortComponentName(key), object.mName }));
            }
        }
        return object;
    }

    /// A script whose file is gone is saved with no reference, and isn't one here: the engine skips it and its values too
    fn AddScripts(self: *Walker, file: FileId, object: *ObjectNode, saved: std.json.Value) !void {
        if (saved != .array) return;
        for (saved.array.items) |script| {
            if (script != .object) continue;
            const ref = script.object.get("Script") orelse continue;
            if (ref != .object) continue;
            const script_file = FileRefOf(ref.object, null) orelse continue;
            try self.Add(script_file.mRoot, script_file.mPath, file, try std.fmt.allocPrint(self.mArena, "script on \"{s}\"", .{object.mName}));

            var use: ScriptUse = .{ .mFile = .{ .mRoot = script_file.mRoot, .mPath = try Normalize(self.mArena, script_file.mPath) } };
            try self.mResult.mLoadedScripts.getPtr(use.mFile.mRoot).put(self.mArena, use.mFile.mPath, {});
            if (script.object.get("Values")) |values| {
                if (values == .object) {
                    use.mValues = values.object;
                    var iter = values.object.iterator();
                    while (iter.next()) |entry| {
                        const via = try std.fmt.allocPrint(self.mArena, "{s} of {s} on \"{s}\"", .{ entry.key_ptr.*, std.fs.path.basename(script_file.mPath), object.mName });
                        try self.ScanValue(entry.value_ptr.*, file, null, via);
                    }
                }
            }
            try object.mScripts.append(self.mArena, use);
        }
    }

    fn AddChildren(self: *Walker, file: FileId, object: *ObjectNode, saved: std.json.Value, kind: ObjectKind) !void {
        if (saved != .array) return;
        for (saved.array.items) |child| {
            if (child != .object) continue;
            try object.mChildren.append(self.mArena, try self.BuildObject(file, child.object, kind));
        }
    }
};

/// What a .zig file declares. Its top level fields are its variables, and its public functions whose third parameter is an
/// object are its hooks and event handlers, the same third parameter ScriptExport.OwnerOf goes by. The compiler sees a
/// script's types, but a walk only has their names, following the file's own `const X = Y.Z`s
fn ParseScript(arena: std.mem.Allocator, source: []const u8) !ScriptFile {
    const terminated = try arena.dupeSentinel(u8, source, 0);
    const tree = try Ast.parse(arena, terminated, .{ .mode = .zig });
    var script: ScriptFile = .{ .mSyntaxErrors = tree.errors.len };

    //tokens, not text: a comment isn't one, so one that mentions Widgets doesn't count
    for (tree.tokens.items(.tag), 0..) |tag, index| {
        if (tag == .identifier and std.mem.eql(u8, tree.tokenSlice(@intCast(index)), "Widgets")) script.mUsesWidgets = true;
    }

    var aliases: std.StringHashMapUnmanaged([]const u8) = .empty;
    for (tree.rootDecls()) |decl| {
        const var_decl = tree.fullVarDecl(decl) orelse continue;
        const init_node = var_decl.ast.init_node.unwrap() orelse continue;
        try aliases.put(arena, tree.tokenSlice(var_decl.ast.mut_token + 1), tree.getNodeSource(init_node));
    }

    var fn_buffer: [1]Ast.Node.Index = undefined;
    for (tree.rootDecls()) |decl| {
        if (tree.fullContainerField(decl)) |field| {
            const type_node = field.ast.type_expr.unwrap() orelse continue;
            const written = tree.getNodeSource(type_node);
            const type_name = ResolveTypeName(&aliases, written);
            try script.mVariables.append(arena, .{
                .mName = tree.tokenSlice(field.ast.main_token),
                .mType = written,
                .mObject = ObjectKindOfType(type_name),
                .mFileRef = FileRefKindOfType(type_name),
            });
        } else if (tree.fullFnProto(&fn_buffer, decl)) |proto| {
            if (proto.visib_token == null) continue;
            const name_token = proto.name_token orelse continue;
            var params = proto.iterate(&tree);
            const self_param = params.next() orelse continue;
            const self_type = self_param.type_expr orelse continue;
            if (!std.mem.startsWith(u8, tree.getNodeSource(self_type), "*")) continue;
            _ = params.next() orelse continue;
            const owner_param = params.next() orelse continue;
            const owner_type = owner_param.type_expr orelse continue;
            const owner = ObjectKindOfType(ResolveTypeName(&aliases, tree.getNodeSource(owner_type))) orelse continue;
            if (script.mOwner == null) script.mOwner = owner;
            try script.mFunctions.append(arena, tree.tokenSlice(name_token));
        }
    }
    return script;
}

/// The name `written` comes down to: IM.Entity, and an Entity declared `const Entity = @import("IM").Entity`, are both Entity
fn ResolveTypeName(aliases: *const std.StringHashMapUnmanaged([]const u8), written: []const u8) []const u8 {
    var name = LastPart(written);
    for (0..8) |_| {
        const alias = aliases.get(name) orelse return name;
        const next = LastPart(alias);
        if (std.mem.eql(u8, next, name)) return name;
        name = next;
    }
    return name;
}

fn LastPart(written: []const u8) []const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, written, '.') orelse return written;
    return written[dot + 1 ..];
}

/// The object type a script names with this type, as Imaginengion.zig exports them
fn ObjectKindOfType(name: []const u8) ?ObjectKind {
    if (std.mem.eql(u8, name, "Entity")) return .Entity;
    if (std.mem.eql(u8, name, "SceneLayer")) return .Scene;
    if (std.mem.eql(u8, name, "Player")) return .Player;
    if (std.mem.eql(u8, name, "GameContext")) return .GameContext;
    return null;
}

fn FileRefKindOfType(name: []const u8) ?ObjectKind {
    if (std.mem.eql(u8, name, "EntityRef")) return .Entity;
    if (std.mem.eql(u8, name, "SceneRef")) return .Scene;
    if (std.mem.eql(u8, name, "PlayerRef")) return .Player;
    if (std.mem.eql(u8, name, "GameContextRef")) return .GameContext;
    return null;
}

/// The file a saved JSON object is a reference to (AssetHandle.FileRef), null if it isn't one
pub fn FileRefOf(object: std.json.ObjectMap, default_root: ?FileRoot) ?FileId {
    const path = object.get("Path") orelse return null;
    if (path != .string) return null;

    const root = if (object.get("PathType")) |path_type| blk: {
        if (path_type != .string) return null;
        break :blk std.meta.stringToEnum(FileRoot, path_type.string) orelse return null;
    } else default_root orelse return null;

    return .{ .mRoot = root, .mPath = path.string };
}

/// `path` with / between folders
pub fn Normalize(arena: std.mem.Allocator, path: []const u8) ![]const u8 {
    const normalized = try arena.dupe(u8, path);
    std.mem.replaceScalar(u8, normalized, '\\', '/');
    return normalized;
}

/// The name a saved NameComponent holds
fn NameOf(saved: std.json.Value) []const u8 {
    if (saved != .object) return "";
    const name = saved.object.get("Name") orelse return "";
    return if (name == .string) name.string else "";
}

/// The UUID a saved UUIDComponent holds
fn SavedUUIDOf(saved: std.json.Value) ?u64 {
    if (saved != .object) return null;
    return UUIDOf(saved.object.get("UUID") orelse return null);
}

/// A UUID as JSON has it: a u64 too big for an i64 comes as a number string
fn UUIDOf(value: std.json.Value) ?u64 {
    return switch (value) {
        .integer => |i| if (i < 0) null else @intCast(i),
        .number_string => |s| std.fmt.parseInt(u64, s, 10) catch null,
        else => null,
    };
}

fn AddSymbols(arena: std.mem.Allocator, result: *Result, file: FileId, object: *const ObjectNode) anyerror!void {
    if (object.mUUID) |uuid| try result.mSymbols.put(arena, uuid, .{ .mFile = file, .mKind = object.mKind, .mName = object.mName });
    for (object.mChildren.items) |*child| try AddSymbols(arena, result, file, child);
}

/// Finds what's saved on `object` and everything under it that points at another object
fn BindLinks(arena: std.mem.Allocator, result: *const Result, object: *ObjectNode) anyerror!void {
    for (COMPONENT_LINKS) |row| {
        const component = object.mComponents.get(row.mComponent) orelse continue;
        if (component != .object) continue;
        const uuid = UUIDOf(component.object.get(row.mField) orelse continue) orelse continue;
        const field = try std.fmt.allocPrint(arena, "{s}.{s}", .{ ShortComponentName(row.mComponent), row.mField });
        try object.mLinks.append(arena, MakeLink(result, field, uuid, row.mWants));
    }
    for (object.mScripts.items) |*use| {
        const script = result.mScriptFiles.getPtrConst(use.mFile.mRoot).getPtr(use.mFile.mPath) orelse continue;
        const values = use.mValues orelse continue;
        for (script.mVariables.items) |variable| {
            const saved = values.get(variable.mName) orelse continue;
            if (variable.mObject) |wants| {
                const uuid = UUIDOf(saved) orelse continue;
                try use.mLinks.append(arena, MakeLink(result, variable.mName, uuid, wants));
            } else if (variable.mFileRef) |wants| {
                if (saved != .object) continue;
                const uuid = UUIDOf(saved.object.get("Object") orelse continue) orelse continue;
                try use.mLinks.append(arena, MakeLink(result, variable.mName, uuid, wants));
            }
        }
    }
    for (object.mChildren.items) |*child| try BindLinks(arena, result, child);
}

fn MakeLink(result: *const Result, field: []const u8, uuid: u64, wants: ObjectKind) ObjectLink {
    return .{ .mField = field, .mUUID = uuid, .mWants = wants, .mTarget = result.mSymbols.get(uuid) };
}

/// Adds `object` and everything under it to `counts`
fn AddCounts(arena: std.mem.Allocator, counts: *ObjectCounts, object: *const ObjectNode) anyerror!void {
    const kind = counts.getPtr(object.mKind);
    kind.mObjects += 1;
    kind.mScripts += object.mScripts.items.len;
    for (object.mComponents.keys()) |component| {
        const count = try kind.mComponents.getOrPutValue(arena, component, 0);
        count.value_ptr.* += 1;
    }
    for (object.mChildren.items) |*child| try AddCounts(arena, counts, child);
}

fn SortCounts(counts: *ObjectCounts) void {
    for (&counts.values) |*kind| SortByName(&kind.mComponents);
}

/// `map`, a std.StringArrayHashMapUnmanaged, in order of its keys
fn SortByName(map: anytype) void {
    const SortContext = struct {
        mNames: []const []const u8,
        pub fn lessThan(self: @This(), left: usize, right: usize) bool {
            return std.mem.lessThan(u8, self.mNames[left], self.mNames[right]);
        }
    };
    map.sort(SortContext{ .mNames = map.keys() });
}

fn ObjectFileLessThan(_: void, left: ObjectFile, right: ObjectFile) bool {
    return std.mem.lessThan(u8, left.mFile.mPath, right.mFile.mPath);
}

/// What the engine needs on its own goes first
fn FileLinkLessThan(_: void, left: FileLink, right: FileLink) bool {
    const left_from = left.mFrom orelse return right.mFrom != null;
    const right_from = right.mFrom orelse return false;
    if (left_from.mRoot != right_from.mRoot) return left_from.mRoot == .Prj;
    return std.mem.lessThan(u8, left_from.mPath, right_from.mPath);
}

/// What an object file with this extension has at its root, null for any other file
fn ObjectKindOf(extension: []const u8) ?ObjectKind {
    if (HasExtension(extension, &.{".imsc"})) return .Scene;
    if (HasExtension(extension, &.{".imen"})) return .Entity;
    if (HasExtension(extension, &.{".impl"})) return .Player;
    if (HasExtension(extension, &.{".imgc"})) return .GameContext;
    return null;
}

/// The object type held by a file at `path`, null for a file that doesn't hold one
pub fn ObjectKindOfFile(path: []const u8) ?ObjectKind {
    return ObjectKindOf(std.fs.path.extension(path));
}

fn HasExtension(extension: []const u8, wanted: []const []const u8) bool {
    for (wanted) |want| {
        if (std.ascii.eqlIgnoreCase(extension, want)) return true;
    }
    return false;
}

fn IsSetting(file: FileId) bool {
    return file.mRoot == .Prj and std.mem.startsWith(u8, file.mPath, SETTINGS_FOLDER ++ "/");
}

/// What `result` doesn't have of the project's files, not counting what's only for building it or a font it gets as its
/// atlas, and of the stock scripts
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
                if (!result.mProject.contains(path) and !result.mFonts.getPtrConst(.Prj).contains(path)) try not_needed.mProject.append(arena, path);
            },
            else => {},
        }
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

/// Deletes everything in `game_path`, a game's folder in zig-out, that isn't part of the game: installing only ever adds
/// files, so what an earlier build needed would stay there. Returns how many files it deleted
pub fn RemoveLeftovers(arena: std.mem.Allocator, io: std.Io, game_path: []const u8, game_name: []const u8, result: *const Result) !usize {
    var game_files: FileSet = .empty;
    try game_files.put(arena, "ImaginGame.exe", {});
    try game_files.put(arena, try std.fmt.allocPrint(arena, "{s}.bat", .{game_name}), {});
    for (result.mProject.keys()) |path| try game_files.put(arena, try std.fmt.allocPrint(arena, "{s}/{s}", .{ game_name, path }), {});
    for (result.mEngine.keys()) |path| try game_files.put(arena, path, {});

    var dir = try std.Io.Dir.cwd().openDir(io, game_path, .{ .iterate = true });
    defer dir.close(io);

    var leftovers: std.ArrayList([]const u8) = .empty;
    var folders: std.ArrayList([]const u8) = .empty;
    var walker = try dir.walkSelectively(arena);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        const path = try Normalize(arena, entry.path);
        switch (entry.kind) {
            .directory => {
                try folders.append(arena, path);
                try walker.enter(io, entry);
            },
            else => if (!game_files.contains(path)) try leftovers.append(arena, path),
        }
    }

    for (leftovers.items) |path| try dir.deleteFile(io, path);
    //a folder comes before what's in it, so from the end every folder has had its own folders tried. One with something in
    //it is meant to fail
    var index = folders.items.len;
    while (index > 0) {
        index -= 1;
        dir.deleteDir(io, folders.items[index]) catch {};
    }
    return leftovers.items.len;
}

/// What `zig build game` prints about a game
pub fn WriteReport(out: *std.Io.Writer, game_name: []const u8, result: *const Result, not_needed: *const NotNeeded) !void {
    try out.print("{s}: {d} files needed\n", .{ game_name, result.mProject.count() + result.mEngine.count() });
    try WriteCounts(out, "project", result.mProject.keys());
    try WriteCounts(out, "engine", result.mEngine.keys());
    try WriteObjectCounts(out, result);

    const not_needed_count = not_needed.mProject.items.len + not_needed.mEngine.items.len;
    if (not_needed_count > 0) {
        try out.print("Left out ({d}):\n", .{not_needed_count});
        for (not_needed.mProject.items) |path| try out.print("  {s}\n", .{path});
        for (not_needed.mEngine.items) |path| try out.print("  (engine) {s}\n", .{EngineRelative(path)});
    }

    const font_count = result.mFonts.getPtrConst(.Prj).count() + result.mFonts.getPtrConst(.Eng).count();
    if (font_count > 0) {
        try out.print("Fonts, shipped as their atlas ({d}):\n", .{font_count});
        for (std.enums.values(FileRoot)) |root| {
            for (result.mFonts.getPtrConst(root).keys()) |path| {
                try out.writeAll("  ");
                try WriteFileId(out, .{ .mRoot = root, .mPath = path });
                try out.writeAll("\n");
            }
        }
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
        if (ObjectKindOf(extension) != null) {
            object_files += 1;
        } else if (HasExtension(extension, &.{".zig"})) {
            scripts += 1;
        } else {
            other += 1;
        }
    }
    try out.print("  {s} {d}: object files {d}, scripts {d}, other {d}\n", .{ label, paths.len, object_files, scripts, other });
}

/// The objects saved in all the object files together, then in each one
fn WriteObjectCounts(out: *std.Io.Writer, result: *const Result) !void {
    if (result.mObjectFiles.items.len == 0) return;

    try out.print("Objects in {d} object files:\n  all of them\n", .{result.mObjectFiles.items.len});
    try WriteKindCounts(out, &result.mObjectTotals);
    for (result.mObjectFiles.items) |*file| {
        try out.writeAll("  ");
        try WriteFileId(out, file.mFile);
        try out.writeAll("\n");
        try WriteKindCounts(out, &file.mCounts);
    }
}

/// A file as the report shows it
pub fn WriteFileId(out: *std.Io.Writer, file: FileId) !void {
    const prefix = if (file.mRoot == .Eng) "(engine) " else "";
    try out.print("{s}{s}", .{ prefix, EngineRelative(file.mPath) });
}

/// A line for each type of object there are any of
fn WriteKindCounts(out: *std.Io.Writer, counts: *const ObjectCounts) !void {
    for (std.enums.values(ObjectKind)) |object_kind| {
        const kind = counts.getPtrConst(object_kind);
        if (kind.mObjects == 0) continue;
        try out.print("    {s} {d}: scripts {d}", .{ @tagName(object_kind), kind.mObjects, kind.mScripts });
        var components = kind.mComponents.iterator();
        while (components.next()) |component| {
            try out.print(", {s} {d}", .{ ShortComponentName(component.key_ptr.*), component.value_ptr.* });
        }
        try out.writeAll("\n");
    }
}

/// What `zig build game -Dtrees` adds to the report: the whole forest
pub fn WriteForest(out: *std.Io.Writer, result: *const Result) !void {
    try WriteTrees(out, result);
    try WriteScripts(out, result);
    try WriteFileLinks(out, result);
}

/// Every object file's objects, with what each one holds and what its scripts save
pub fn WriteTrees(out: *std.Io.Writer, result: *const Result) !void {
    for (result.mObjectFiles.items) |*file| {
        try WriteFileId(out, file.mFile);
        try out.writeAll("\n");
        try WriteObject(out, result, &file.mObject, 1);
    }
}

fn WriteObject(out: *std.Io.Writer, result: *const Result, object: *const ObjectNode, depth: usize) anyerror!void {
    try WriteIndent(out, depth);
    try out.print("{s} \"{s}\"", .{ @tagName(object.mKind), object.mName });
    if (object.mComponents.count() > 0) {
        try out.writeAll(" [");
        for (object.mComponents.keys(), 0..) |component, i| {
            try out.print("{s}{s}", .{ if (i > 0) " " else "", ShortComponentName(component) });
        }
        try out.writeAll("]");
    }
    try out.writeAll("\n");

    for (object.mLinks.items) |*link| {
        try WriteIndent(out, depth + 1);
        try out.print("{s} = ", .{link.mField});
        try WriteLinkTarget(out, link);
        try out.writeAll("\n");
    }
    for (object.mScripts.items) |*use| {
        try WriteIndent(out, depth + 1);
        try out.print("script {s}\n", .{std.fs.path.basename(use.mFile.mPath)});
        try WriteSavedValues(out, result, use, depth + 2);
    }
    for (object.mChildren.items) |*child| try WriteObject(out, result, child, depth + 1);
}

fn WriteSavedValues(out: *std.Io.Writer, result: *const Result, use: *const ScriptUse, depth: usize) !void {
    const values = use.mValues orelse return;
    const script = result.mScriptFiles.getPtrConst(use.mFile.mRoot).getPtr(use.mFile.mPath);
    var iter = values.iterator();
    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const variable = if (script) |found| found.GetVariable(name) else null;
        try WriteIndent(out, depth);
        try out.print("{s}: {s} = ", .{ name, if (variable) |known| known.mType else "(not in the script)" });
        try WriteSavedValue(out, use, variable, entry.value_ptr.*);
        try out.writeAll("\n");
    }
}

/// A variable's saved value: what it links to if that's known, or as it's saved
fn WriteSavedValue(out: *std.Io.Writer, use: *const ScriptUse, variable: ?*const Variable, value: std.json.Value) !void {
    if (variable) |known| {
        if (known.mFileRef != null and value == .object) {
            if (value.object.get("File")) |file_value| {
                if (file_value == .object) {
                    if (FileRefOf(file_value.object, null)) |file| return try WriteFileId(out, file);
                }
            }
        }
        for (use.mLinks.items) |*link| {
            if (std.mem.eql(u8, link.mField, known.mName)) return try WriteLinkTarget(out, link);
        }
    }
    switch (value) {
        .float => |float| try out.print("{d}", .{float}),
        else => try std.json.Stringify.value(value, .{}, out),
    }
}

fn WriteLinkTarget(out: *std.Io.Writer, link: *const ObjectLink) !void {
    const target = link.mTarget orelse return try out.print("{d}, which no needed file has", .{link.mUUID});
    try out.print("{s} \"{s}\" in ", .{ @tagName(target.mKind), target.mName });
    try WriteFileId(out, target.mFile);
}

/// Every .zig file reached and what it declares
fn WriteScripts(out: *std.Io.Writer, result: *const Result) !void {
    try out.writeAll("Code files:\n");
    for (std.enums.values(FileRoot)) |root| {
        var iter = result.mScriptFiles.getPtrConst(root).iterator();
        while (iter.next()) |entry| {
            const script = entry.value_ptr;
            try out.writeAll("  ");
            try WriteFileId(out, .{ .mRoot = root, .mPath = entry.key_ptr.* });
            if (script.mOwner) |owner| {
                try out.print(": goes on {s},", .{@tagName(owner)});
                for (script.mFunctions.items) |function| try out.print(" {s}", .{function});
                try out.writeAll("\n");
            } else {
                try out.writeAll(": not a script\n");
            }
            for (script.mVariables.items) |variable| try out.print("    {s}: {s}\n", .{ variable.mName, variable.mType });
        }
    }
}

/// Every link between files, under the file that names the other
fn WriteFileLinks(out: *std.Io.Writer, result: *const Result) !void {
    try out.writeAll("What each file names:\n");
    var last_from: ?FileId = null;
    for (result.mFileLinks.items, 0..) |link, i| {
        if (i == 0 or !SameFile(link.mFrom, last_from)) {
            try out.writeAll("  ");
            if (link.mFrom) |from| try WriteFileId(out, from) else try out.writeAll("the engine");
            try out.writeAll("\n");
        }
        last_from = link.mFrom;
        try out.writeAll("    ");
        try WriteFileId(out, link.mTo);
        try out.print(" ({s})\n", .{link.mVia});
    }
}

fn SameFile(left: ?FileId, right: ?FileId) bool {
    const left_file = left orelse return right == null;
    const right_file = right orelse return false;
    return left_file.mRoot == right_file.mRoot and std.mem.eql(u8, left_file.mPath, right_file.mPath);
}

fn WriteIndent(out: *std.Io.Writer, depth: usize) !void {
    for (0..depth) |_| try out.writeAll("  ");
}

fn ShortComponentName(name: []const u8) []const u8 {
    const suffix = "Component";
    return if (std.mem.endsWith(u8, name, suffix)) name[0 .. name.len - suffix.len] else name;
}

/// An engine path as the build's list of assets has it, from the engine's assets folder
fn EngineRelative(path: []const u8) []const u8 {
    const prefix = EngineFiles.ASSETS_PATH ++ "/";
    return if (std.mem.startsWith(u8, path, prefix)) path[prefix.len..] else path;
}
