//! Working out which files a game needs (GameBuild/ProjectWalk.zig): what it follows, what it says is missing, what it says
//! is copied for nothing, and the report made of that. Run with `zig build test`.
const std = @import("std");
const EngineFiles = @import("../../GameBuild/EngineFiles.zig");
const ProjectWalk = @import("../../GameBuild/ProjectWalk.zig");

const THEME_FONT = EngineFiles.ASSETS_PATH ++ "/fonts/default/static/ChironGoRoundTC-Bold.ttf";
const STOCK_FOLDER = EngineFiles.ASSETS_PATH ++ "/" ++ EngineFiles.STOCK_SCRIPTS_FOLDER;

/// A project in game/ and what it needs of an engine in engine/, in a temporary folder
const TestGame = struct {
    mTmpDir: std.testing.TmpDir,
    mArena: std.heap.ArenaAllocator,

    fn Init() !TestGame {
        var game: TestGame = .{ .mTmpDir = std.testing.tmpDir(.{}), .mArena = .init(std.testing.allocator) };
        errdefer game.Deinit();

        for (EngineFiles.COPIED_ASSETS) |asset| {
            try game.WriteFile(try game.Join("engine/" ++ EngineFiles.ASSETS_PATH, asset), "");
        }
        //a theme's font doesn't have to say where it's from
        try game.WriteFile("engine/" ++ EngineFiles.DEFAULT_THEME, "{\"Styles\":{\"Button\":{\"Font\":{\"Path\":\"" ++ THEME_FONT ++ "\"}}}}");
        try game.WriteFile("engine/" ++ STOCK_FOLDER ++ "/Choose.zig", "");
        try game.WriteFile("engine/" ++ STOCK_FOLDER ++ "/Toggle.zig", "");
        return game;
    }

    fn Deinit(self: *TestGame) void {
        self.mArena.deinit();
        self.mTmpDir.cleanup();
    }

    fn Join(self: *TestGame, folder: []const u8, path: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.mArena.allocator(), "{s}/{s}", .{ folder, path });
    }

    fn WriteFile(self: *TestGame, path: []const u8, text: []const u8) !void {
        if (std.fs.path.dirname(path)) |folder| try self.mTmpDir.dir.createDirPath(std.testing.io, folder);
        try self.mTmpDir.dir.writeFile(std.testing.io, .{ .sub_path = path, .data = text });
    }

    fn Write(self: *TestGame, path: []const u8, text: []const u8) !void {
        try self.WriteFile(try self.Join("game", path), text);
    }

    fn FullPath(self: *TestGame, sub_path: []const u8) ![]const u8 {
        const folder = try self.mTmpDir.dir.realPathFileAlloc(std.testing.io, ".", self.mArena.allocator());
        return try std.fs.path.join(self.mArena.allocator(), &.{ folder, sub_path });
    }

    fn Walk(self: *TestGame) !ProjectWalk.Result {
        return try ProjectWalk.WalkProject(self.mArena.allocator(), std.testing.io, try self.FullPath("game"), try self.FullPath("engine"), "game.imprj");
    }

    fn FindNotNeeded(self: *TestGame, result: *const ProjectWalk.Result) !ProjectWalk.NotNeeded {
        return try ProjectWalk.FindNotNeeded(self.mArena.allocator(), std.testing.io, try self.FullPath("game"), try self.FullPath("engine"), result);
    }

    /// A project whose entries are these three files, each with nothing in it
    fn WriteEntries(self: *TestGame) !void {
        try self.Write("game.imprj",
            \\{"Name": "game", "EntryScene": "scenes/Main.imsc", "EntryPlayer": "players/Main.impl", "EntryGameContext": "gc/Main.imgc"}
        );
        try self.Write("scenes/Main.imsc", "{}");
        try self.Write("players/Main.impl", "{}");
        try self.Write("gc/Main.imgc", "{}");
    }
};

fn ExpectPaths(expected: []const []const u8, got: []const []const u8) !void {
    try std.testing.expectEqual(expected.len, got.len);
    for (expected, got) |want, path| try std.testing.expectEqualStrings(want, path);
}

test "the walk follows the entries, what objects save at any depth, script variables, fonts and imports" {
    var game = try TestGame.Init();
    defer game.Deinit();

    try game.Write("game.imprj",
        \\{"Name": "game", "WindowIcon": "icon.png", "EntryScene": "scenes/Main.imsc", "EntryPlayer": "players/Main.impl", "EntryGameContext": "gc/Main.imgc"}
    );
    try game.Write("icon.png", "");
    try game.Write("ProjectSettings/Audio.json",
        \\{"Buses": {}}
    );
    try game.Write("scenes/Main.imsc",
        \\{"Entities": [{"Children": [{
        \\    "SurfaceComponent": {"Texture": {"Path": "textures/Ball.png", "PathType": "Prj"}},
        \\    "TextComponent": {"Font": {"Path": "fonts/Title.ttf", "PathType": "Prj"}},
        \\    "Scripts": [{
        \\        "Script": {"Path": "scripts/Play.zig", "PathType": "Prj"},
        \\        "Values": {"Next": {"File": {"Path": "scenes/Next.imsc", "PathType": "Prj"}, "Object": 5}, "Speed": 2}
        \\    }]
        \\}]}]}
    );
    try game.Write("scenes/Next.imsc",
        \\{"Scripts": [{"Script": {"Path": "
    ++ STOCK_FOLDER ++ "/Choose.zig" ++
        \\", "PathType": "Eng"}}], "AudioComponent": {"Audio": {"Path": "music/Theme.mp3", "PathType": "Prj"}}}
    );
    try game.Write("players/Main.impl", "{}");
    try game.Write("gc/Main.imgc",
        \\{"EnumComponent": {"EnumFile": {"Path": "gc/State.zig", "PathType": "Prj"}}}
    );
    try game.Write("gc/State.zig", "");
    try game.Write("textures/Ball.png", "");
    try game.Write("music/Theme.mp3", "");
    try game.Write("fonts/Title.ttf", "");
    try game.Write("fonts/Title.json", "");
    try game.Write("fonts/Title.png", "");
    //imported by name, and through what that imports. The commented out import is nothing
    try game.Write("scripts/Play.zig", "const Score = @import(\"Score\");\n//const Old = @import(\"Old\");");
    try game.Write("events/Score.zig", "const Shared = @import(\"Shared\");");
    try game.Write("events/Shared.zig", "");

    //none of these are named by anything
    try game.Write("scripts/Old.zig", "");
    try game.Write("textures/Unused.png", "");
    try game.Write("notes.txt", "");
    //and these never go into a game anyway
    try game.Write("build.zig", "");
    try game.Write("build.zig.zon", "");
    try game.Write("zig-out/game/Copy.png", "");

    const result = try game.Walk();
    try std.testing.expectEqual(0, result.mMissing.items.len);
    try std.testing.expectEqual(0, result.mUnreadable.items.len);
    try std.testing.expectEqual(0, result.mUnsetEntries.items.len);

    for ([_][]const u8{
        "game.imprj",        "icon.png",          "ProjectSettings/Audio.json", "scenes/Main.imsc", "scenes/Next.imsc",
        "players/Main.impl", "gc/Main.imgc",      "gc/State.zig",               "textures/Ball.png", "music/Theme.mp3",
        "fonts/Title.ttf",   "fonts/Title.json",  "fonts/Title.png",            "scripts/Play.zig", "events/Score.zig",
        "events/Shared.zig",
    }) |path| {
        if (!result.mProject.contains(path)) {
            std.debug.print("not found: {s}\n", .{path});
            return error.TestExpectedFile;
        }
    }
    try std.testing.expectEqual(16, result.mProject.count());

    const not_needed = try game.FindNotNeeded(&result);
    try ExpectPaths(&.{ "notes.txt", "scripts/Old.zig", "textures/Unused.png" }, not_needed.mProject.items);
}

test "the engine's files every game needs are found, and what a theme names, and only the stock scripts a game uses" {
    var game = try TestGame.Init();
    defer game.Deinit();
    try game.WriteEntries();
    try game.Write("scenes/Main.imsc",
        \\{"Scripts": [{"Script": {"Path": "
    ++ STOCK_FOLDER ++ "/Choose.zig" ++
        \\", "PathType": "Eng"}}]}
    );

    const result = try game.Walk();
    try std.testing.expectEqual(0, result.mMissing.items.len);
    for (EngineFiles.ALWAYS_NEEDED) |path| try std.testing.expect(result.mEngine.contains(path));
    //the theme's font and its atlas, which only the theme leads to
    try std.testing.expect(result.mEngine.contains(THEME_FONT));
    try std.testing.expect(result.mEngine.contains(EngineFiles.ASSETS_PATH ++ "/fonts/default/static/ChironGoRoundTC-Bold.json"));
    try std.testing.expect(result.mEngine.contains(STOCK_FOLDER ++ "/Choose.zig"));

    const not_needed = try game.FindNotNeeded(&result);
    try ExpectPaths(&.{STOCK_FOLDER ++ "/Toggle.zig"}, not_needed.mEngine.items);
}

test "a file that isn't there, an entry that isn't set and a file that isn't JSON are all reported, and don't stop the walk" {
    var game = try TestGame.Init();
    defer game.Deinit();
    try game.Write("game.imprj",
        \\{"Name": "game", "EntryScene": "scenes/Main.imsc", "EntryGameContext": "gc/Broken.imgc"}
    );
    try game.Write("scenes/Main.imsc",
        \\{"A": {"Path": "textures/Gone.png", "PathType": "Prj"}, "B": {"Path": "textures/Gone.png", "PathType": "Prj"},
        \\ "C": {"Path": "fonts/Bare.ttf", "PathType": "Prj"}, "D": {"Path": "textures/There.png", "PathType": "Prj"},
        \\ "Scripts": [{"Script": {"Path": "scripts/Play.zig", "PathType": "Prj"}}]}
    );
    try game.Write("gc/Broken.imgc", "not json");
    //no atlas next to it
    try game.Write("fonts/Bare.ttf", "");
    try game.Write("textures/There.png", "");
    try game.Write("scripts/Play.zig", "const Gone = @import(\"NoSuchFile\");");

    const result = try game.Walk();

    try std.testing.expect(result.mProject.contains("textures/There.png"));
    try std.testing.expect(!result.mProject.contains("textures/Gone.png"));

    try ExpectPaths(&.{"EntryPlayer"}, result.mUnsetEntries.items);
    try std.testing.expectEqual(1, result.mUnreadable.items.len);
    try std.testing.expectEqualStrings("gc/Broken.imgc", result.mUnreadable.items[0].mPath);

    //named twice, said once
    var gone = false;
    var atlas_files: usize = 0;
    var import = false;
    for (result.mMissing.items) |missing| {
        if (std.mem.eql(u8, missing.mPath, "textures/Gone.png")) {
            try std.testing.expect(!gone);
            gone = true;
            try std.testing.expectEqualStrings("scenes/Main.imsc", missing.mFrom);
        } else if (std.mem.startsWith(u8, missing.mPath, "fonts/Bare.")) {
            atlas_files += 1;
            try std.testing.expectEqualStrings("fonts/Bare.ttf", missing.mFrom);
        } else if (std.mem.eql(u8, missing.mPath, "NoSuchFile.zig")) {
            import = true;
            try std.testing.expectEqualStrings("scripts/Play.zig", missing.mFrom);
        }
    }
    try std.testing.expect(gone and import);
    try std.testing.expectEqual(2, atlas_files);
    try std.testing.expectEqual(4, result.mMissing.items.len);
}

test "a project file that can't be read is the walk's one error" {
    var game = try TestGame.Init();
    defer game.Deinit();
    try game.Write("other.txt", "");
    try std.testing.expectError(error.FileNotFound, game.Walk());
}

test "the report counts files by kind and lists what isn't needed and what's missing" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var result: ProjectWalk.Result = .{};
    for ([_][]const u8{ "game.imprj", "scenes/Main.imsc", "players/Main.impl", "scripts/Play.zig", "a.png" }) |path| {
        try result.mProject.put(arena, path, {});
    }
    try result.mEngine.put(arena, EngineFiles.PLAIN_TEXTURE, {});

    var not_needed: ProjectWalk.NotNeeded = .{};
    try not_needed.mProject.append(arena, "notes.txt");
    try not_needed.mEngine.append(arena, STOCK_FOLDER ++ "/Toggle.zig");

    var buffer: [1024]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buffer);
    try ProjectWalk.WriteReport(&out, "game", &result, &not_needed);
    try std.testing.expectEqualStrings(
        \\game: 6 files needed
        \\  project 5: object files 2, scripts 1, other 2
        \\  engine 1: object files 0, scripts 0, other 1
        \\Not needed, still copied (2):
        \\  notes.txt
        \\  (engine) scripts/UI/Toggle.zig
        \\Missing: none
        \\
    , out.buffered());

    try result.mUnsetEntries.append(arena, "EntryPlayer");
    try result.mMissing.append(arena, .{ .mRoot = .Prj, .mPath = "b.png", .mFrom = "scenes/Main.imsc" });
    try result.mMissing.append(arena, .{ .mRoot = .Eng, .mPath = EngineFiles.DEFAULT_SOUND, .mFrom = "the engine" });
    try result.mUnreadable.append(arena, .{ .mPath = "gc/Broken.imgc", .mReason = "SyntaxError" });

    out = .fixed(&buffer);
    try ProjectWalk.WriteReport(&out, "game", &result, &.{});
    try std.testing.expectEqualStrings(
        \\game: 6 files needed
        \\  project 5: object files 2, scripts 1, other 2
        \\  engine 1: object files 0, scripts 0, other 1
        \\Missing (4):
        \\  EntryPlayer isn't set in the project file
        \\  b.png, named by scenes/Main.imsc
        \\  (engine) sounds/DefaultSound.mp3, named by the engine
        \\  gc/Broken.imgc can't be read: SyntaxError
        \\
    , out.buffered());
}
