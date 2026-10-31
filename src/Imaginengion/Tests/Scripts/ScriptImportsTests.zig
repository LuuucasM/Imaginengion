//! Finding the project files a script imports (Scripts/ScriptImports.zig): what counts as an import, finding project files
//! by their names wherever they are, following imports through the files found, and the two mistakes it reports.
//! Run with `zig build test`.
const std = @import("std");
const ScriptImports = @import("../../Scripts/ScriptImports.zig");

fn ExpectImports(source: []const u8, expected: []const ScriptImports.Import) !void {
    var imports = try ScriptImports.ImportsOf(std.testing.allocator, source);
    defer imports.deinit(std.testing.allocator);
    try std.testing.expectEqual(expected.len, imports.items.len);
    for (expected, imports.items) |want, got| {
        try std.testing.expectEqual(std.meta.activeTag(want), std.meta.activeTag(got));
        switch (want) {
            inline else => |text, tag| try std.testing.expectEqualStrings(text, @field(got, @tagName(tag))),
        }
    }
}

test "an import of a project file is found by name or by path, and never std, IM, a comment or a string" {
    try ExpectImports(
        \\const std = @import("std");
        \\const IM = @import("IM");
        \\const ScoreEvent = @import("ScoreEvent");
        \\const Shared = @import( "Shared.zig" ); const Other = @import("Other");
        \\//const Old = @import("OldEvent");
        \\const url = "http://example"; const Late = @import("Late"); // @import("InComment")
        \\const text =
        \\    \\@import("InMultilineString")
        \\;
    , &.{
        .{ .Name = "ScoreEvent" },
        .{ .Path = "Shared.zig" },
        .{ .Name = "Other" },
        .{ .Name = "Late" },
    });
}

/// A project in a temporary folder
const TestProject = struct {
    mTmpDir: std.testing.TmpDir,
    mArena: std.heap.ArenaAllocator,

    fn Init() TestProject {
        return .{ .mTmpDir = std.testing.tmpDir(.{}), .mArena = .init(std.testing.allocator) };
    }

    fn Deinit(self: *TestProject) void {
        self.mArena.deinit();
        self.mTmpDir.cleanup();
    }

    fn Write(self: *TestProject, path: []const u8, text: []const u8) !void {
        if (std.fs.path.dirname(path)) |folder| try self.mTmpDir.dir.createDirPath(std.testing.io, folder);
        try self.mTmpDir.dir.writeFile(std.testing.io, .{ .sub_path = path, .data = text });
    }

    fn Path(self: *TestProject, sub_path: []const u8) ![]const u8 {
        const folder = try self.mTmpDir.dir.realPathFileAlloc(std.testing.io, ".", self.mArena.allocator());
        return try std.fs.path.resolveAlloc(self.mArena.allocator(), &.{ folder, sub_path });
    }
};

test "a script's imports are followed through the files it reaches, by name and by path" {
    var project = TestProject.Init();
    defer project.Deinit();
    try project.Write("scripts/Ball.zig", "const Helpers = @import(\"PongHelpers\");");
    try project.Write("shared/PongHelpers.zig", "const ScoreEvent = @import(\"ScoreEvent\");\nconst Inner = @import(\"Inner.zig\");");
    try project.Write("shared/Inner.zig", "const ScoreEvent = @import(\"ScoreEvent\");");
    try project.Write("events/deep/ScoreEvent.zig", "pub const Phase = .AfterUpdate;");
    //in the project but not imported, and in a folder a project's own files never are
    try project.Write("scripts/Unused.zig", "");
    try project.Write("zig-out/ScoreEvent.zig", "");

    const arena = project.mArena.allocator();
    const files = try ScriptImports.FindProjectFiles(arena, std.testing.io, try project.Path("."));
    try std.testing.expect(files.mDuplicate == null);
    const collected = try ScriptImports.Collect(arena, std.testing.io, try project.Path("scripts/Ball.zig"), &files);

    try std.testing.expect(collected.mMissing == null);
    try std.testing.expectEqual(@as(usize, 2), collected.mNamed.items.len);
    try std.testing.expectEqualStrings("PongHelpers", collected.mNamed.items[0].Name);
    try std.testing.expectEqualStrings(try project.Path("shared/PongHelpers.zig"), collected.mNamed.items[0].Path);
    try std.testing.expectEqualStrings(try project.Path("events/deep/ScoreEvent.zig"), collected.mNamed.items[1].Path);

    //every file it depends on, each once, and not the script itself
    try std.testing.expectEqual(@as(usize, 3), collected.mDependencies.items.len);
    for ([_][]const u8{ "shared/PongHelpers.zig", "shared/Inner.zig", "events/deep/ScoreEvent.zig" }) |expected| {
        const path = try project.Path(expected);
        for (collected.mDependencies.items) |dependency| {
            if (std.mem.eql(u8, dependency, path)) break;
        } else return error.TestExpectedDependency;
    }
}

test "the build.zig at the project's top isn't a project file, one further in is" {
    var project = TestProject.Init();
    defer project.Deinit();
    try project.Write("build.zig", "");
    try project.Write("zig-pkg/Package.zig", "");

    const arena = project.mArena.allocator();
    var files = try ScriptImports.FindProjectFiles(arena, std.testing.io, try project.Path("."));
    try std.testing.expect(files.mByName.get("build") == null);
    try std.testing.expect(files.mByName.get("Package") == null);

    try project.Write("scripts/build.zig", "");
    files = try ScriptImports.FindProjectFiles(arena, std.testing.io, try project.Path("."));
    try std.testing.expect(files.mDuplicate == null);
    try std.testing.expectEqualStrings(try project.Path("scripts/build.zig"), files.mByName.get("build").?);
}

test "a name no project file has, and two project files with one name, are reported" {
    var project = TestProject.Init();
    defer project.Deinit();
    try project.Write("scripts/Ball.zig", "const Gone = @import(\"RenamedEvent\");");
    const arena = project.mArena.allocator();

    var files = try ScriptImports.FindProjectFiles(arena, std.testing.io, try project.Path("."));
    const collected = try ScriptImports.Collect(arena, std.testing.io, try project.Path("scripts/Ball.zig"), &files);
    try std.testing.expectEqualStrings("RenamedEvent", collected.mMissing.?.Name);

    try project.Write("a/Score.zig", "");
    try project.Write("b/Score.zig", "");
    files = try ScriptImports.FindProjectFiles(arena, std.testing.io, try project.Path("."));
    try std.testing.expectEqualStrings("Score", files.mDuplicate.?.Name);
}
