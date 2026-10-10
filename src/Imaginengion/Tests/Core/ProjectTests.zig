//! The project's entries (Core/Project.zig), the scene, player and game mode the game starts from: set from object
//! files inside the project, written to the project file, and read back when the project is opened in a fresh engine. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Project = @import("../../Core/Project.zig");

const TestEngine = struct {
    mEngineContext: *EngineContext,
    mTmpDir: std.testing.TmpDir,

    fn Init() !*TestEngine {
        const self = try std.heap.page_allocator.create(TestEngine);
        self.* = .{
            .mEngineContext = try std.heap.page_allocator.create(EngineContext),
            .mTmpDir = std.testing.tmpDir(.{}),
        };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //file reads/writes go through the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        //the audio settings are one of the project's settings owners
        try engine_context.mAudioManager.InitMixer(engine_context);
        return self;
    }

    fn Deinit(self: *TestEngine) void {
        const engine_context = self.mEngineContext;
        engine_context.mAudioManager.DeinitMixer(engine_context);
        engine_context.mProject.Deinit(engine_context);
        engine_context.mSerializer.Deinit(engine_context.EngineAllocator());
        _ = engine_context._Internal.EngineGPA.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// This test's temporary folder as an absolute path, which is what a project is made with
    fn TmpDirAbsPath(self: *TestEngine) ![]const u8 {
        return try self.mTmpDir.dir.realPathFileAlloc(self.mEngineContext.Io(), ".", self.mEngineContext.FrameAllocator());
    }
};

test "the entries are kept from the project folder, and opening the project brings them back" {
    const saved_engine = try TestEngine.Init();
    defer saved_engine.Deinit();
    const saved_context = saved_engine.mEngineContext;
    const project = &saved_context.mProject;
    const frame_allocator = saved_context.FrameAllocator();

    const project_folder = try saved_engine.TmpDirAbsPath();
    try project.New(saved_context, project_folder);
    try std.testing.expectEqualStrings("", project.GetEntry(.Scene));

    try project.SetEntry(saved_context, .Scene, try std.fs.path.join(frame_allocator, &.{ project_folder, "Scenes", "Main.imsc" }));
    try project.SetEntry(saved_context, .Player, try std.fs.path.join(frame_allocator, &.{ project_folder, "Hero.impl" }));
    try std.testing.expectEqualStrings("Scenes/Main.imsc", project.GetEntry(.Scene));
    try std.testing.expectEqualStrings("Hero.impl", project.GetEntry(.Player));
    try std.testing.expectEqualStrings("", project.GetEntry(.GameContext));

    //only the entry's kind of file, and only one in the project
    const outside_path = try std.fs.path.join(frame_allocator, &.{ std.fs.path.dirname(project_folder).?, "Other.imsc" });
    try std.testing.expectError(error.NotInProject, project.SetEntry(saved_context, .Scene, outside_path));
    const wrong_kind_path = try std.fs.path.join(frame_allocator, &.{ project_folder, "Hero.impl" });
    try std.testing.expectError(error.WrongFileKind, project.SetEntry(saved_context, .GameContext, wrong_kind_path));
    try std.testing.expectEqualStrings("Scenes/Main.imsc", project.GetEntry(.Scene));
    try std.testing.expectEqualStrings("", project.GetEntry(.GameContext));

    //setting one writes the project file, no Save needed
    const loaded_engine = try TestEngine.Init();
    defer loaded_engine.Deinit();
    const loaded_context = loaded_engine.mEngineContext;
    const project_file_name = try std.fmt.allocPrint(loaded_context.FrameAllocator(), "{s}{s}", .{ std.fs.path.basename(project_folder), Project.FILE_EXTENSION });
    const project_file_path = try std.fs.path.join(loaded_context.FrameAllocator(), &.{ project_folder, project_file_name });
    try loaded_context.mProject.Open(loaded_context, project_file_path);
    try std.testing.expectEqualStrings("Scenes/Main.imsc", loaded_context.mProject.GetEntry(.Scene));
    try std.testing.expectEqualStrings("Hero.impl", loaded_context.mProject.GetEntry(.Player));
    try std.testing.expectEqualStrings("", loaded_context.mProject.GetEntry(.GameContext));
}
