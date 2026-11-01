//! Working out which files a game needs (GameBuild/ProjectWalk.zig): what it follows, what it says is missing, what it says
//! is copied for nothing, the forest it builds, the checks run over that (GameBuild/ForestChecks.zig), and the report made
//! of it all. Run with `zig build test`.
const std = @import("std");
const EngineFiles = @import("../../GameBuild/EngineFiles.zig");
const ForestChecks = @import("../../GameBuild/ForestChecks.zig");
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

fn FindObjectFile(result: *const ProjectWalk.Result, path: []const u8) *const ProjectWalk.ObjectFile {
    for (result.mObjectFiles.items) |*file| {
        if (std.mem.eql(u8, file.mFile.mPath, path)) return file;
    }
    @panic("no such object file");
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

test "an object file gives its tree of objects, of the right types, with their components and scripts" {
    var game = try TestGame.Init();
    defer game.Deinit();
    try game.WriteEntries();
    try game.Write("scenes/Main.imsc",
        \\{"UUIDComponent": {"UUID": 1}, "NameComponent": {"Name": "Main"}, "SceneComponent": {},
        \\ "Scripts": [{"Script": {"Path": "scripts/Start.zig", "PathType": "Prj"}}, {"Script": null}],
        \\ "Children": [{"NameComponent": {"Name": "Sound"}, "AudioComponent": {}}],
        \\ "Entities": [{"NameComponent": {"Name": "Ball"}, "TransformComponent": {},
        \\               "Children": [{"NameComponent": {"Name": "Shine"}, "TransformComponent": {}, "ShapeComponent": {}}]}]}
    );
    try game.Write("scripts/Start.zig", "");

    const result = try game.Walk();

    const scene = FindObjectFile(&result, "scenes/Main.imsc").mObject;
    try std.testing.expectEqual(.Scene, scene.mKind);
    try std.testing.expectEqualStrings("Main", scene.mName);
    //what every object has isn't listed
    try ExpectPaths(&.{"SceneComponent"}, scene.mComponents.keys());
    //a script with no file isn't one
    try std.testing.expectEqual(1, scene.mScripts.items.len);
    try std.testing.expectEqualStrings("scripts/Start.zig", scene.mScripts.items[0].mFile.mPath);

    try std.testing.expectEqual(2, scene.mChildren.items.len);
    const sound = scene.mChildren.items[0];
    try std.testing.expectEqual(.Scene, sound.mKind);
    try std.testing.expectEqualStrings("Sound", sound.mName);

    const ball = scene.mChildren.items[1];
    try std.testing.expectEqual(.Entity, ball.mKind);
    try std.testing.expectEqual(1, ball.mChildren.items.len);
    try std.testing.expectEqual(.Entity, ball.mChildren.items[0].mKind);
    try std.testing.expectEqualStrings("Shine", ball.mChildren.items[0].mName);

    try std.testing.expectEqual(.Player, FindObjectFile(&result, "players/Main.impl").mObject.mKind);
    try std.testing.expectEqual(.GameContext, FindObjectFile(&result, "gc/Main.imgc").mObject.mKind);
}

test "an object file that's JSON but not an object is reported and has no tree" {
    var game = try TestGame.Init();
    defer game.Deinit();
    try game.WriteEntries();
    try game.Write("scenes/Main.imsc", "[]");

    const result = try game.Walk();

    try std.testing.expectEqual(2, result.mObjectFiles.items.len);
    try std.testing.expectEqual(1, result.mUnreadable.items.len);
    try std.testing.expectEqualStrings("scenes/Main.imsc", result.mUnreadable.items[0].mPath);
    try std.testing.expectEqualStrings("NotAnObject", result.mUnreadable.items[0].mReason);
}

test "the counts and trees are per file and per type of object, and a file named twice counts once" {
    var game = try TestGame.Init();
    defer game.Deinit();
    try game.WriteEntries();
    try game.Write("scenes/Main.imsc",
        \\{"NameComponent": {"Name": "Main"}, "AudioComponent": {},
        \\ "Scripts": [{"Script": {"Path": "scripts/Start.zig", "PathType": "Prj"}, "Values": {"Next": {"File": {"Path": "scenes/Next.imsc", "PathType": "Prj"}}, "Other": {"File": {"Path": "scenes/Next.imsc", "PathType": "Prj"}}}}],
        \\ "Entities": [
        \\   {"NameComponent": {"Name": "A"}, "TransformComponent": {}, "ShapeComponent": {}, "Scripts": [{"Script": {"Path": "scripts/Start.zig", "PathType": "Prj"}}]},
        \\   {"NameComponent": {"Name": "B"}, "TransformComponent": {}, "StaticBodyTag": {}}
        \\ ]}
    );
    try game.Write("scenes/Next.imsc",
        \\{"NameComponent": {"Name": "Next"}, "AudioComponent": {}, "Entities": [{"NameComponent": {"Name": "C"}, "TransformComponent": {}}]}
    );
    try game.Write("scripts/Start.zig", "");

    const result = try game.Walk();

    const main = FindObjectFile(&result, "scenes/Main.imsc").mCounts;
    try std.testing.expectEqual(1, main.get(.Scene).mObjects);
    try std.testing.expectEqual(2, main.get(.Entity).mObjects);
    try std.testing.expectEqual(1, main.get(.Entity).mScripts);
    try std.testing.expectEqual(2, main.get(.Entity).mComponents.get("TransformComponent").?);

    const totals = result.mObjectTotals;
    try std.testing.expectEqual(2, totals.get(.Scene).mObjects);
    try std.testing.expectEqual(3, totals.get(.Entity).mObjects);
    try std.testing.expectEqual(3, totals.get(.Entity).mComponents.get("TransformComponent").?);
    try std.testing.expectEqual(2, totals.get(.Scene).mComponents.get("AudioComponent").?);
    //the entries' other two files
    try std.testing.expectEqual(1, totals.get(.Player).mObjects);
    try std.testing.expectEqual(1, totals.get(.GameContext).mObjects);

    var buffer: [2048]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buffer);
    try ProjectWalk.WriteTrees(&out, &result);
    try std.testing.expectEqualStrings(
        \\gc/Main.imgc
        \\  GameContext ""
        \\players/Main.impl
        \\  Player ""
        \\scenes/Main.imsc
        \\  Scene "Main" [Audio]
        \\    script Start.zig
        \\      Next: (not in the script) = {"File":{"Path":"scenes/Next.imsc","PathType":"Prj"}}
        \\      Other: (not in the script) = {"File":{"Path":"scenes/Next.imsc","PathType":"Prj"}}
        \\    Entity "A" [Transform Shape]
        \\      script Start.zig
        \\    Entity "B" [Transform StaticBodyTag]
        \\scenes/Next.imsc
        \\  Scene "Next" [Audio]
        \\    Entity "C" [Transform]
        \\
    , out.buffered());

    out = .fixed(&buffer);
    try ProjectWalk.WriteReport(&out, "game", &result, &.{});
    const report = out.buffered();
    const start = std.mem.indexOf(u8, report, "Objects in").?;
    const end = std.mem.indexOf(u8, report, "Missing").?;
    try std.testing.expectEqualStrings(
        \\Objects in 4 object files:
        \\  all of them
        \\    Scene 2: scripts 1, Audio 2
        \\    Entity 3: scripts 1, Shape 1, StaticBodyTag 1, Transform 3
        \\    Player 1: scripts 0
        \\    GameContext 1: scripts 0
        \\  gc/Main.imgc
        \\    GameContext 1: scripts 0
        \\  players/Main.impl
        \\    Player 1: scripts 0
        \\  scenes/Main.imsc
        \\    Scene 1: scripts 1, Audio 1
        \\    Entity 2: scripts 1, Shape 1, StaticBodyTag 1, Transform 2
        \\  scenes/Next.imsc
        \\    Scene 1: scripts 0, Audio 1
        \\    Entity 1: scripts 0, Transform 1
        \\
    , report[start..end]);
}

fn FindScriptFile(result: *const ProjectWalk.Result, path: []const u8) *const ProjectWalk.ScriptFile {
    return result.mScriptFiles.getPtrConst(.Prj).getPtr(path) orelse @panic("no such script file");
}

fn HasLink(result: *const ProjectWalk.Result, from: []const u8, to: []const u8, via: []const u8) bool {
    for (result.mFileLinks.items) |link| {
        const link_from = link.mFrom orelse continue;
        if (std.mem.eql(u8, link_from.mPath, from) and std.mem.eql(u8, link.mTo.mPath, to) and std.mem.eql(u8, link.mVia, via)) return true;
    }
    return false;
}

test "a script's code gives its owner, variables and hooks, whatever it calls its types, and comments aren't code" {
    var game = try TestGame.Init();
    defer game.Deinit();
    try game.WriteEntries();
    try game.Write("scenes/Main.imsc",
        \\{"Scripts": [{"Script": {"Path": "scripts/OnScene.zig", "PathType": "Prj"}}],
        \\ "Entities": [{"Scripts": [{"Script": {"Path": "scripts/Named.zig", "PathType": "Prj"}}]}]}
    );
    try game.Write("scripts/OnScene.zig",
        \\const IM = @import("IM");
        \\const Layer = IM.SceneLayer;
        \\Speed: f32 = 1.0,
        \\Thing: Layer = .uninit,
        \\Next: IM.SceneRef = .uninit,
        \\//Old: IM.Entity = .uninit,
        \\//pub fn OnKeyPressed(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity) !IM.ScriptResult {}
        \\pub fn OnUpdate(self: *@This(), _: *IM.EngineContext, _: Layer) !IM.ScriptResult { _ = self; return .Continue; }
        \\fn Helper(self: *@This(), a: u32, owner: IM.Entity) void { _ = .{ self, a, owner }; }
    );
    //a local type called what an object type is called is its own type
    try game.Write("scripts/Named.zig",
        \\const Player = enum { One, Two };
        \\Who: Player = .One,
        \\pub fn OnScore(self: *@This(), engine_context: *Context, owner: @import("IM").Entity, event: *const Score) !void { _ = .{ self, engine_context, owner, event }; }
    );
    //a game's enum: a .zig file with no hooks
    try game.Write("gc/Main.imgc",
        \\{"EnumComponent": {"EnumFile": {"Path": "gc/State.zig", "PathType": "Prj"}}}
    );
    try game.Write("gc/State.zig", "pub const State = enum { A };");

    const result = try game.Walk();

    const on_scene = FindScriptFile(&result, "scripts/OnScene.zig");
    try std.testing.expectEqual(.Scene, on_scene.mOwner.?);
    try ExpectPaths(&.{"OnUpdate"}, on_scene.mFunctions.items);
    try std.testing.expectEqual(3, on_scene.mVariables.items.len);
    try std.testing.expectEqualStrings("Speed", on_scene.mVariables.items[0].mName);
    try std.testing.expectEqual(null, on_scene.mVariables.items[0].mObject);
    try std.testing.expectEqual(.Scene, on_scene.mVariables.items[1].mObject.?);
    try std.testing.expectEqual(.Scene, on_scene.mVariables.items[2].mFileRef.?);
    try std.testing.expectEqual(0, on_scene.mSyntaxErrors);

    const named = FindScriptFile(&result, "scripts/Named.zig");
    try std.testing.expectEqual(.Entity, named.mOwner.?);
    try ExpectPaths(&.{"OnScore"}, named.mFunctions.items);
    try std.testing.expectEqual(null, named.mVariables.items[0].mObject);

    try std.testing.expectEqual(null, FindScriptFile(&result, "gc/State.zig").mOwner);
}

test "links between files say who names what and why, and a circle of files is walked once" {
    var game = try TestGame.Init();
    defer game.Deinit();
    try game.WriteEntries();
    try game.Write("scenes/Main.imsc",
        \\{"NameComponent": {"Name": "Main"}, "Scripts": [{"Script": {"Path": "scripts/Go.zig", "PathType": "Prj"},
        \\ "Values": {"Next": {"File": {"Path": "scenes/Next.imsc", "PathType": "Prj"}}}}],
        \\ "Entities": [{"NameComponent": {"Name": "Ball"}, "SurfaceComponent": {"Texture": {"Path": "ball.png", "PathType": "Prj"}}}]}
    );
    try game.Write("scenes/Next.imsc",
        \\{"NameComponent": {"Name": "Next"}, "Scripts": [{"Script": {"Path": "scripts/Go.zig", "PathType": "Prj"},
        \\ "Values": {"Next": {"File": {"Path": "scenes/Main.imsc", "PathType": "Prj"}}}}]}
    );
    try game.Write("scripts/Go.zig", "const Shared = @import(\"Shared\");");
    try game.Write("scripts/Shared.zig", "");
    try game.Write("ball.png", "");

    const result = try game.Walk();

    try std.testing.expect(HasLink(&result, "game.imprj", "scenes/Main.imsc", "EntryScene"));
    try std.testing.expect(HasLink(&result, "scenes/Main.imsc", "scripts/Go.zig", "script on \"Main\""));
    try std.testing.expect(HasLink(&result, "scenes/Main.imsc", "scenes/Next.imsc", "Next of Go.zig on \"Main\""));
    try std.testing.expect(HasLink(&result, "scenes/Main.imsc", "ball.png", "Surface on \"Ball\""));
    try std.testing.expect(HasLink(&result, "scenes/Next.imsc", "scripts/Go.zig", "script on \"Next\""));
    try std.testing.expect(HasLink(&result, "scenes/Next.imsc", "scenes/Main.imsc", "Next of Go.zig on \"Next\""));
    try std.testing.expect(HasLink(&result, "scripts/Go.zig", "scripts/Shared.zig", "import"));

    //what the engine needs by itself comes first, named by no file
    try std.testing.expectEqual(null, result.mFileLinks.items[0].mFrom);

    //the circle: each file is in the forest once, though named twice
    var main_trees: usize = 0;
    for (result.mObjectFiles.items) |file| {
        if (std.mem.eql(u8, file.mFile.mPath, "scenes/Main.imsc")) main_trees += 1;
    }
    try std.testing.expectEqual(1, main_trees);
}

test "UUID links find their objects in any file, however the UUID is saved" {
    var game = try TestGame.Init();
    defer game.Deinit();
    try game.WriteEntries();
    //too big for an i64, so JSON has it as a number string
    try game.Write("scenes/Main.imsc",
        \\{"UUIDComponent": {"UUID": 11458502199759248617}, "NameComponent": {"Name": "Main"}, "SpawnPossComponent": {"EntityRef": 7},
        \\ "Scripts": [{"Script": {"Path": "scripts/OnScene.zig", "PathType": "Prj"},
        \\   "Values": {"Boss": 7, "Score": 9, "Speed": 2, "Next": {"File": {"Path": "scenes/Main.imsc", "PathType": "Prj"}, "Object": 11458502199759248617}}}],
        \\ "Entities": [{"UUIDComponent": {"UUID": 7}, "NameComponent": {"Name": "Boss"}}]}
    );
    try game.Write("gc/Main.imgc",
        \\{"UUIDComponent": {"UUID": 9}, "NameComponent": {"Name": "Score"}}
    );
    try game.Write("players/Main.impl",
        \\{"NameComponent": {"Name": "One"}, "OverlayComponent": {"Scene": 11458502199759248617}}
    );
    try game.Write("scripts/OnScene.zig",
        \\const IM = @import("IM");
        \\Boss: IM.Entity = .uninit,
        \\Score: IM.GameContext = .uninit,
        \\Speed: f32 = 1.0,
        \\Next: IM.SceneRef = .uninit,
        \\pub fn OnUpdate(self: *@This(), engine_context: *IM.EngineContext, owner: IM.SceneLayer) !IM.ScriptResult { _ = .{ self, engine_context, owner }; return .Continue; }
    );

    const result = try game.Walk();

    const scene = FindObjectFile(&result, "scenes/Main.imsc").mObject;
    try std.testing.expectEqual(11458502199759248617, scene.mUUID.?);
    try std.testing.expectEqualStrings("SpawnPoss.EntityRef", scene.mLinks.items[0].mField);
    try std.testing.expectEqualStrings("Boss", scene.mLinks.items[0].mTarget.?.mName);

    const links = scene.mScripts.items[0].mLinks.items;
    try std.testing.expectEqual(3, links.len);
    try std.testing.expectEqualStrings("Boss", links[0].mField);
    try std.testing.expectEqualStrings("Boss", links[0].mTarget.?.mName);
    try std.testing.expectEqualStrings("Score", links[1].mTarget.?.mName);
    try std.testing.expectEqualStrings("gc/Main.imgc", links[1].mTarget.?.mFile.mPath);
    try std.testing.expectEqualStrings("Next", links[2].mField);
    try std.testing.expectEqualStrings("Main", links[2].mTarget.?.mName);

    const player = FindObjectFile(&result, "players/Main.impl").mObject;
    try std.testing.expectEqualStrings("Main", player.mLinks.items[0].mTarget.?.mName);

    const checks = try ForestChecks.Run(game.mArena.allocator(), &result);
    try ExpectPaths(&.{}, checks.mProblems.items);
}

test "the checks say which saved values, refs, owners and links are wrong" {
    var game = try TestGame.Init();
    defer game.Deinit();
    try game.WriteEntries();
    try game.Write("players/Main.impl",
        \\{"NameComponent": {"Name": "One"}, "OverlayComponent": {"Scene": 404}}
    );
    try game.Write("scenes/Main.imsc",
        \\{"UUIDComponent": {"UUID": 1}, "NameComponent": {"Name": "Main"}, "Entities": [
        \\  {"NameComponent": {"Name": "Stale"}, "Scripts": [{"Script": {"Path": "scripts/Good.zig", "PathType": "Prj"},
        \\     "Values": {"Next": {"File": {"Path": "scenes/Main.imsc", "PathType": "Prj"}}, "Gone": 5}}]},
        \\  {"NameComponent": {"Name": "NoValues"}, "Scripts": [{"Script": {"Path": "scripts/Good.zig", "PathType": "Prj"}}]},
        \\  {"NameComponent": {"Name": "BadFile"}, "Scripts": [{"Script": {"Path": "scripts/Good.zig", "PathType": "Prj"},
        \\     "Values": {"Next": {"File": {"Path": "a.png", "PathType": "Prj"}}}}]},
        \\  {"NameComponent": {"Name": "BadLinks"}, "Scripts": [{"Script": {"Path": "scripts/Links.zig", "PathType": "Prj"},
        \\     "Values": {"Dangling": 404, "WrongKind": 1}}]},
        \\  {"NameComponent": {"Name": "OnWrong"}, "Scripts": [{"Script": {"Path": "scripts/OnPlayer.zig", "PathType": "Prj"}}]},
        \\  {"NameComponent": {"Name": "NotScript"}, "Scripts": [{"Script": {"Path": "scripts/Event.zig", "PathType": "Prj"}}]},
        \\  {"NameComponent": {"Name": "Broken"}, "Scripts": [{"Script": {"Path": "scripts/Broken.zig", "PathType": "Prj"}}]},
        \\  {"NameComponent": {"Name": "Fine"}, "Scripts": [{"Script": {"Path": "scripts/Links.zig", "PathType": "Prj"}}]}
        \\]}
    );
    try game.Write("a.png", "");
    try game.Write("scripts/Good.zig",
        \\const IM = @import("IM");
        \\Next: IM.SceneRef = .uninit,
        \\pub fn OnUpdate(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity) !IM.ScriptResult { _ = .{ self, engine_context, owner }; return .Continue; }
    );
    //object variables left empty are fine: code can set those, unlike file refs
    try game.Write("scripts/Links.zig",
        \\const IM = @import("IM");
        \\Dangling: IM.Entity = .uninit,
        \\WrongKind: IM.Entity = .uninit,
        \\pub fn OnUpdate(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity) !IM.ScriptResult { _ = .{ self, engine_context, owner }; return .Continue; }
    );
    try game.Write("scripts/OnPlayer.zig",
        \\const IM = @import("IM");
        \\pub fn OnUpdate(self: *@This(), engine_context: *IM.EngineContext, _: IM.Player) !IM.ScriptResult { _ = .{ self, engine_context }; return .Continue; }
    );
    try game.Write("scripts/Event.zig", "pub const Phase = 0;");
    try game.Write("scripts/Broken.zig", "pub fn OnUpdate(self: *@This() {");

    const result = try game.Walk();
    const checks = try ForestChecks.Run(game.mArena.allocator(), &result);
    try ExpectPaths(&.{
        "players/Main.impl: \"One\" Overlay.Scene wants Scene 404, which no needed file has",
        "scenes/Main.imsc: \"Stale\" Good.zig: saves Gone, which the script no longer has",
        "scenes/Main.imsc: \"NoValues\" Good.zig: Next (IM.SceneRef) has no file set",
        "scenes/Main.imsc: \"BadFile\" Good.zig: Next (IM.SceneRef) names a.png, which isn't that kind of file",
        "scenes/Main.imsc: \"BadLinks\" Links.zig: Dangling wants Entity 404, which no needed file has",
        "scenes/Main.imsc: \"BadLinks\" Links.zig: WrongKind wants Entity, but 1 is the Scene \"Main\" in scenes/Main.imsc",
        "scenes/Main.imsc: Entity \"OnWrong\" has OnPlayer.zig, whose hooks are for Player",
        "scenes/Main.imsc: \"NotScript\" has Event.zig, which has no hooks or event handlers",
        "scenes/Main.imsc: \"Broken\" has Broken.zig, which has no hooks or event handlers",
        "scripts/Broken.zig: has syntax errors",
    }, checks.mProblems.items);
}

test "the whole forest and the checks are printed as the report shows them" {
    var game = try TestGame.Init();
    defer game.Deinit();
    try game.WriteEntries();
    try game.Write("scenes/Main.imsc",
        \\{"UUIDComponent": {"UUID": 1}, "NameComponent": {"Name": "Main"}, "Entities": [
        \\  {"UUIDComponent": {"UUID": 2}, "NameComponent": {"Name": "Ball"}, "Scripts": [{"Script": {"Path": "scripts/Ball.zig", "PathType": "Prj"},
        \\     "Values": {"Speed": 1.5, "Self": 2, "Lost": 404, "Next": {"File": {"Path": "scenes/Main.imsc", "PathType": "Prj"}}, "Old": true}}]}]}
    );
    try game.Write("scripts/Ball.zig",
        \\const IM = @import("IM");
        \\Speed: f32 = 1.0,
        \\Self: IM.Entity = .uninit,
        \\Lost: IM.Entity = .uninit,
        \\Next: IM.SceneRef = .uninit,
        \\pub fn OnUpdate(self: *@This(), engine_context: *IM.EngineContext, owner: IM.Entity) !IM.ScriptResult { _ = .{ self, engine_context, owner }; return .Continue; }
    );

    const result = try game.Walk();

    var buffer: [8192]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buffer);
    try ProjectWalk.WriteForest(&out, &result);
    const forest = out.buffered();

    const trees_end = std.mem.indexOf(u8, forest, "What each file names:").?;
    try std.testing.expectEqualStrings(
        \\gc/Main.imgc
        \\  GameContext ""
        \\players/Main.impl
        \\  Player ""
        \\scenes/Main.imsc
        \\  Scene "Main"
        \\    Entity "Ball"
        \\      script Ball.zig
        \\        Speed: f32 = 1.5
        \\        Self: IM.Entity = Entity "Ball" in scenes/Main.imsc
        \\        Lost: IM.Entity = 404, which no needed file has
        \\        Next: IM.SceneRef = scenes/Main.imsc
        \\        Old: (not in the script) = true
        \\Code files:
        \\  scripts/Ball.zig: goes on Entity, OnUpdate
        \\    Speed: f32
        \\    Self: IM.Entity
        \\    Lost: IM.Entity
        \\    Next: IM.SceneRef
        \\
    , forest[0..trees_end]);
    try std.testing.expect(std.mem.indexOf(u8, forest,
        \\  scenes/Main.imsc
        \\    scripts/Ball.zig (script on "Ball")
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, forest, "scenes/Main.imsc (Next of Ball.zig on \"Ball\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, forest, "  the engine\n") != null);

    const checks = try ForestChecks.Run(game.mArena.allocator(), &result);
    out = .fixed(&buffer);
    try ForestChecks.WriteChecks(&out, &checks);
    try std.testing.expectEqualStrings(
        \\Problems (2):
        \\  scenes/Main.imsc: "Ball" Ball.zig: saves Old, which the script no longer has
        \\  scenes/Main.imsc: "Ball" Ball.zig: Lost wants Entity 404, which no needed file has
        \\
    , out.buffered());

    out = .fixed(&buffer);
    try ForestChecks.WriteChecks(&out, &.{});
    try std.testing.expectEqualStrings("Problems: none\n", out.buffered());
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
