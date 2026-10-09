//! The editor's shell (Programs/EditorShell.zig): what it builds, and which panes are shown. No window needed. Run with
//! `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const EditorShell = @import("../../Programs/EditorShell.zig");
const PhysicsManager = @import("../../Physics/PhysicsManager.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mRoot: Entity = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mRoot = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        _ = try self.mRoot.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

test "the shell shows the first tab of each tab bar and the play preview, and hides it when asked" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const shell = try EditorShell.Build(engine_context, world.mRoot, .{ .StockScripts = false });

    try std.testing.expect(EditorShell.IsShown(shell.mScenesPage));
    try std.testing.expect(!EditorShell.IsShown(shell.mEntitiesPage));
    try std.testing.expect(EditorShell.IsShown(shell.mComponentsPage));
    try std.testing.expect(!EditorShell.IsShown(shell.mScriptsPage));
    try std.testing.expect(EditorShell.IsShown(shell.mContentBrowserPane));
    try std.testing.expect(EditorShell.IsShown(shell.mViewportArea));

    try std.testing.expect(EditorShell.IsShown(shell.mPlayPane));
    try shell.ShowPlayPreview(engine_context, false);
    try std.testing.expect(!EditorShell.IsShown(shell.mPlayPane));
    try std.testing.expect(!EditorShell.IsShown(shell.mCenter.Divider));
    try shell.ShowPlayPreview(engine_context, true);
    try std.testing.expect(EditorShell.IsShown(shell.mPlayPane));

    try std.testing.expect(EditorShell.IsShown(shell.mMenuBar));
}
