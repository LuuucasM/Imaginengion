const std = @import("std");
const EngineContext = @import("EngineContext.zig");
const Tracy = @import("Tracy.zig");
const Project = @This();

//the project that is open, if any: its folder, its project file, and the settings the engine keeps per project.
//A project is a folder holding a <name>.imprj project file, and a ProjectSettings folder with one file per owner:
//
//    MyGame/
//        MyGame.imprj
//        ProjectSettings/
//            Audio.json
//            ...

pub const FILE_EXTENSION = ".imprj";
pub const SETTINGS_FOLDER = "ProjectSettings";
const FORMAT_VERSION: u32 = 1;

/// The engine level systems that keep settings per project, by their EngineContext field. Each one's type declares:
///     pub const ProjectSettingsName: []const u8, so its file is ProjectSettings/<ProjectSettingsName>.json
///     pub fn SaveProjectSettings(self, engine_context: *EngineContext, write_stream: *std.json.Stringify) !void
///     pub fn LoadProjectSettings(self, engine_context: *EngineContext, scanner: *std.json.Scanner) !void
///     pub fn ResetProjectSettings(self, engine_context: *EngineContext) !void, back to what a new project starts with
/// Each owner only ever sees its own settings, never the file they are in, and gets a file to itself so saving one
/// never rewrites another's and version control shows a change against the system it belongs to
const SETTINGS_OWNERS = [_][]const u8{
    "mAudioManager",
    "mUIManager",
};

const STRINGIFY_OPTIONS: std.json.Stringify.Options = .{ .whitespace = .indent_2 };

/// What the project file holds. Nothing reads it back yet: it marks the folder as a project, and has the version so
/// a later format change can tell old projects apart
const ProjectFile = struct {
    Name: []const u8,
    Version: u32,
};

mDirectory: ?std.Io.Dir = null,
/// The project folder's absolute path, empty while no project is open
mPath: std.ArrayList(u8) = .empty,
/// The project file's name inside the folder, <name>.imprj
mFileName: std.ArrayList(u8) = .empty,

/// Frees what the project holds without saving. The editor saves when it closes, before this runs
pub fn Deinit(self: *Project, engine_context: *EngineContext) void {
    self.CloseFolder(engine_context);
    self.mPath.deinit(engine_context.EngineAllocator());
    self.mFileName.deinit(engine_context.EngineAllocator());
}

pub fn IsOpen(self: Project) bool {
    return self.mDirectory != null;
}

/// The project folder. Only valid while a project is open
pub fn GetDirectory(self: Project) std.Io.Dir {
    return self.mDirectory.?;
}

/// The project folder's absolute path, empty while no project is open
pub fn GetPath(self: *const Project) []const u8 {
    return self.mPath.items;
}

/// A path inside the project folder, made absolute
pub fn GetAbsPath(self: *const Project, allocator: std.mem.Allocator, rel_path: []const u8) ![]const u8 {
    return try std.fs.path.join(allocator, &[_][]const u8{ self.mPath.items, rel_path });
}

/// An absolute path inside the project folder, made relative to it
pub fn GetRelPath(self: *const Project, abs_path: []const u8) []const u8 {
    return abs_path[self.mPath.items.len + 1 ..];
}

/// Makes folder_abs_path a new project: a <folder name>.imprj project file, and every owner's default settings.
/// The project that was open is saved and closed first
pub fn New(self: *Project, engine_context: *EngineContext, folder_abs_path: []const u8) !void {
    const zone = Tracy.ZoneInit("Project::New", @src());
    defer zone.Deinit();

    try self.Close(engine_context);

    const file_name = try std.fmt.allocPrint(engine_context.FrameAllocator(), "{s}{s}", .{ std.fs.path.basename(folder_abs_path), FILE_EXTENSION });
    try self.OpenFolder(engine_context, folder_abs_path, file_name);

    inline for (SETTINGS_OWNERS) |owner_field| {
        try @field(engine_context, owner_field).ResetProjectSettings(engine_context);
    }

    try self.Save(engine_context);
}

/// Opens the project whose project file is project_file_abs_path and loads every owner's settings. An owner without a
/// settings file (a project older than it) gets its defaults. The project that was open is saved and closed first
pub fn Open(self: *Project, engine_context: *EngineContext, project_file_abs_path: []const u8) !void {
    const zone = Tracy.ZoneInit("Project::Open", @src());
    defer zone.Deinit();

    try self.Close(engine_context);

    try self.OpenFolder(engine_context, std.fs.path.dirname(project_file_abs_path).?, std.fs.path.basename(project_file_abs_path));

    inline for (SETTINGS_OWNERS) |owner_field| {
        try self.LoadOwnerSettings(engine_context, owner_field);
    }

    //references into the settings that were waiting on them (e.g. an AudioComponent's bus) can be resolved now
    engine_context.mSerializer.ResolveUUIDs();
}

/// Writes the project file and every owner's settings file. Does nothing while no project is open
pub fn Save(self: *Project, engine_context: *EngineContext) !void {
    if (!self.IsOpen()) return;

    const zone = Tracy.ZoneInit("Project::Save", @src());
    defer zone.Deinit();

    const project_file: ProjectFile = .{ .Name = std.fs.path.stem(self.mFileName.items), .Version = FORMAT_VERSION };
    try self.WriteJson(engine_context, self.mFileName.items, project_file);

    try self.GetDirectory().createDirPath(engine_context.Io(), SETTINGS_FOLDER);
    inline for (SETTINGS_OWNERS) |owner_field| {
        try self.SaveOwnerSettings(engine_context, owner_field);
    }
}

/// Saves and closes the open project, if there is one. What the owners hold stays as it is until the next New or Open
pub fn Close(self: *Project, engine_context: *EngineContext) !void {
    if (!self.IsOpen()) return;
    try self.Save(engine_context);
    self.CloseFolder(engine_context);
}

fn OpenFolder(self: *Project, engine_context: *EngineContext, folder_abs_path: []const u8, file_name: []const u8) !void {
    const engine_allocator = engine_context.EngineAllocator();

    self.mDirectory = try std.Io.Dir.openDirAbsolute(engine_context.Io(), folder_abs_path, .{});
    errdefer self.CloseFolder(engine_context);

    try self.mPath.appendSlice(engine_allocator, folder_abs_path);
    try self.mFileName.appendSlice(engine_allocator, file_name);
}

fn CloseFolder(self: *Project, engine_context: *EngineContext) void {
    if (self.mDirectory) |dir| dir.close(engine_context.Io());
    self.mDirectory = null;
    self.mPath.clearRetainingCapacity();
    self.mFileName.clearRetainingCapacity();
}

fn SettingsPath(comptime owner_field: []const u8) []const u8 {
    return SETTINGS_FOLDER ++ "/" ++ @FieldType(EngineContext, owner_field).ProjectSettingsName ++ ".json";
}

fn SaveOwnerSettings(self: *Project, engine_context: *EngineContext, comptime owner_field: []const u8) !void {
    var out: std.Io.Writer.Allocating = .init(engine_context.FrameAllocator());
    defer out.deinit();

    var write_stream: std.json.Stringify = .{ .writer = &out.writer, .options = STRINGIFY_OPTIONS };
    try @field(engine_context, owner_field).SaveProjectSettings(engine_context, &write_stream);

    //the whole file at once, so a failed save never leaves a half written one behind
    try self.GetDirectory().writeFile(engine_context.Io(), .{ .sub_path = comptime SettingsPath(owner_field), .data = out.written() });
}

fn LoadOwnerSettings(self: *Project, engine_context: *EngineContext, comptime owner_field: []const u8) !void {
    const owner = &@field(engine_context, owner_field);

    const contents = self.GetDirectory().readFileAlloc(engine_context.Io(), comptime SettingsPath(owner_field), engine_context.FrameAllocator(), .unlimited) catch |err| switch (err) {
        error.FileNotFound => return try owner.ResetProjectSettings(engine_context),
        else => return err,
    };

    var scanner = std.json.Scanner.initCompleteInput(engine_context.FrameAllocator(), contents);
    defer scanner.deinit();
    try owner.LoadProjectSettings(engine_context, &scanner);
}

fn WriteJson(self: *Project, engine_context: *EngineContext, rel_path: []const u8, value: anytype) !void {
    var out: std.Io.Writer.Allocating = .init(engine_context.FrameAllocator());
    defer out.deinit();

    var write_stream: std.json.Stringify = .{ .writer = &out.writer, .options = STRINGIFY_OPTIONS };
    try write_stream.write(value);

    try self.GetDirectory().writeFile(engine_context.Io(), .{ .sub_path = rel_path, .data = out.written() });
}
