//! Finding the project files a script imports, for build_script.zig. A script imports a project file by its name,
//! `@import("ScoreEvent")`, wherever the file is in the project (so file names have to be different), or a file next to
//! it by path, `@import("Shared.zig")`. An @import's argument is always a string literal, so reading the text finds
//! every one. What it finds is what the script is built with (a module for each file imported by name) and what the
//! engine watches to rebuild the script when one changes (ScriptInfo.mDependencies).
//! Only std: the build imports this file too.
const std = @import("std");

/// Modules every script has without looking for them, never project files
const NOT_PROJECT_FILES = [_][]const u8{ "std", "builtin", "root", "IM" };

/// Folders a project's own files are never in: build output and caches, and hidden folders
fn SkipFolder(name: []const u8) bool {
    return name.len == 0 or name[0] == '.' or std.mem.eql(u8, name, "zig-out") or std.mem.eql(u8, name, "zig-cache");
}

pub const Import = union(enum) {
    /// a project file by its name, without .zig: @import("ScoreEvent")
    Name: []const u8,
    /// a file by its path from the importing file: @import("Shared.zig")
    Path: []const u8,
};

/// Every @import in `source` that could be a project file, in order, as slices of `source`. An import in a // comment is
/// left out, so a comment showing one doesn't make a file that isn't there needed
pub fn ImportsOf(allocator: std.mem.Allocator, source: []const u8) !std.ArrayList(Import) {
    var imports: std.ArrayList(Import) = .empty;
    errdefer imports.deinit(allocator);

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const code = line[0..CommentStart(line)];
        var rest = code;
        while (std.mem.indexOf(u8, rest, "@import(")) |at| {
            rest = std.mem.trimStart(u8, rest[at + "@import(".len ..], " \t");
            if (rest.len == 0 or rest[0] != '"') continue;
            const end = std.mem.indexOfScalarPos(u8, rest, 1, '"') orelse break;
            const text = rest[1..end];
            rest = rest[end + 1 ..];

            if (std.mem.endsWith(u8, text, ".zig")) {
                try imports.append(allocator, .{ .Path = text });
            } else if (!IsNotProjectFile(text)) {
                try imports.append(allocator, .{ .Name = text });
            }
        }
    }
    return imports;
}

/// Where a line's // comment starts, its length if it has none. A // inside a string ("http://") isn't one
fn CommentStart(line: []const u8) usize {
    var in_string = false;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        switch (line[i]) {
            '\\' => if (in_string) {
                i += 1;
            } else if (i + 1 < line.len and line[i + 1] == '\\') {
                //a multi-line string's line: none of it is code
                return i;
            },
            '"' => in_string = !in_string,
            '/' => if (!in_string and i + 1 < line.len and line[i + 1] == '/') return i,
            else => {},
        }
    }
    return line.len;
}

fn IsNotProjectFile(name: []const u8) bool {
    for (NOT_PROJECT_FILES) |builtin_name| {
        if (std.mem.eql(u8, name, builtin_name)) return true;
    }
    return false;
}

/// Every .zig file in a project folder, by its name without .zig
pub const ProjectFiles = struct {
    /// name -> absolute path
    mByName: std.StringHashMapUnmanaged([]const u8) = .empty,
    /// every folder looked in, for the build to rerun when one gets a file added, removed or renamed
    mFolders: std.ArrayList([]const u8) = .empty,
    /// two files with the same name, which would make importing it by name ambiguous
    mDuplicate: ?struct { Name: []const u8, First: []const u8, Second: []const u8 } = null,
};

/// Walks `project_path` for its .zig files. Every path found is a normalized one (resolved, the platform's separators),
/// the same as Collect makes of a path import. Memory from `arena`
pub fn FindProjectFiles(arena: std.mem.Allocator, io: std.Io, given_project_path: []const u8) !ProjectFiles {
    const project_path = try std.fs.path.resolveAlloc(arena, &.{given_project_path});
    var files: ProjectFiles = .{};
    var project_dir = try std.Io.Dir.cwd().openDir(io, project_path, .{ .iterate = true });
    defer project_dir.close(io);
    try files.mFolders.append(arena, project_path);

    var walker = try project_dir.walkSelectively(arena);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                if (SkipFolder(entry.basename)) continue;
                try files.mFolders.append(arena, try std.fs.path.join(arena, &.{ project_path, entry.path }));
                try walker.enter(io, entry);
            },
            .file => {
                if (!std.mem.endsWith(u8, entry.basename, ".zig")) continue;
                const name = try arena.dupe(u8, entry.basename[0 .. entry.basename.len - ".zig".len]);
                const path = try std.fs.path.join(arena, &.{ project_path, entry.path });
                const found = try files.mByName.getOrPut(arena, name);
                if (found.found_existing) {
                    if (files.mDuplicate == null) files.mDuplicate = .{ .Name = name, .First = found.value_ptr.*, .Second = path };
                    continue;
                }
                found.value_ptr.* = path;
            },
            else => {},
        }
    }
    return files;
}

/// What a script imports from its project
pub const Collected = struct {
    /// the files it, or anything it imports, imports by name
    mNamed: std.ArrayList(struct { Name: []const u8, Path: []const u8 }) = .empty,
    /// every project file it depends on (by name or by path), not the script itself
    mDependencies: std.ArrayList([]const u8) = .empty,
    /// the first name it imports that no project file has, null when every one was found
    mMissing: ?struct { Name: []const u8, In: []const u8 } = null,
};

/// Follows the imports of the script at `script_path`, and of every project file those reach. Memory from `arena`
pub fn Collect(arena: std.mem.Allocator, io: std.Io, script_path: []const u8, files: *const ProjectFiles) !Collected {
    var collected: Collected = .{};
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var named: std.StringHashMapUnmanaged(void) = .empty;
    var to_read: std.ArrayList([]const u8) = .empty;
    try seen.put(arena, script_path, {});
    try to_read.append(arena, script_path);

    while (to_read.pop()) |path| {
        //one that can't be read is left to the compiler, which says why
        const source = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(64 * 1024 * 1024)) catch continue;
        const imports = try ImportsOf(arena, source);
        for (imports.items) |import| {
            const found: []const u8 = switch (import) {
                .Name => |name| files.mByName.get(name) orelse {
                    if (collected.mMissing == null) collected.mMissing = .{ .Name = name, .In = path };
                    continue;
                },
                .Path => |rel_path| try std.fs.path.resolveAlloc(arena, &.{ std.fs.path.dirname(path) orelse ".", rel_path }),
            };
            //a file imported by name somewhere needs its module, even if it was reached by path first
            if (import == .Name and !named.contains(import.Name)) {
                try named.put(arena, import.Name, {});
                try collected.mNamed.append(arena, .{ .Name = import.Name, .Path = found });
            }
            if (seen.contains(found)) continue;
            try seen.put(arena, found, {});
            try collected.mDependencies.append(arena, found);
            try to_read.append(arena, found);
        }
    }
    return collected;
}
