//! The Audio Buses panel in the editor's own UI (EditorPanels/AudioBusesPanel.zig): its tree built from the bus tree the
//! first time it is open, Master without a name field or Delete, the tree built again when a bus is added, edits written
//! into the buses through the bindings, and node titles following renames. Voices and buses only, through
//! AudioManager.InitMixer: no sound card, window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Bus = @import("../../ECSObjects/Bus.zig");
const AudioBusesPanel = @import("../../EditorPanels/AudioBusesPanel.zig");
const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TextComponent = EntityComponents.TextComponent;
const AttribComponent = EntityComponents.AttribComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const VComponents = @import("../../ECSComponents/VComponents.zig");
const VolumeComponent = VComponents.VolumeComponent;
const NameComponent = VComponents.NameComponent;

const TestEngine = struct {
    mEngineContext: *EngineContext,
    mPanel: AudioBusesPanel = .{},

    fn Init() !*TestEngine {
        const self = try std.heap.page_allocator.create(TestEngine);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //bus UUIDs go through the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        try engine_context.mAudioManager.InitMixer(engine_context);
        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mPanel = try AudioBusesPanel.Build(engine_context, scene, .{ .StockScripts = false });
        return self;
    }

    fn Deinit(self: *TestEngine) void {
        const engine_context = self.mEngineContext;
        self.mPanel.Deinit(engine_context.EngineAllocator());
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mAudioManager.DeinitMixer(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn Master(self: *TestEngine) Bus {
        return self.mEngineContext.mAudioManager.GetMasterBus();
    }
};

fn TextOf(label: Entity) []const u8 {
    return label.GetComponent(TextComponent).?.mText.items;
}

fn Children(entity: Entity, out: []Entity) usize {
    var count: usize = 0;
    var children = entity.GetIterator(.Child);
    while (children.next()) |child| : (count += 1) {
        if (count < out.len) out[count] = child;
    }
    return count;
}

/// A bus node's content: what is under its header
fn ContentOf(title: Entity) Entity {
    const header = title.GetComponent(@import("../../ECS/Components.zig").ChildComponent(Entity.Type)).?.mParent;
    const node = title.mManager.GetEntity(header).GetComponent(@import("../../ECS/Components.zig").ChildComponent(Entity.Type)).?.mParent;
    var parts: [2]Entity = undefined;
    _ = Children(title.mManager.GetEntity(node), &parts);
    return parts[1];
}

/// The widget of a row the inspector made: what comes after its label
fn WidgetOf(row: Entity) Entity {
    var parts: [2]Entity = undefined;
    _ = Children(row, &parts);
    return parts[1];
}

test "the tree is built when the window opens, with no name field or Delete on Master" {
    const test_engine = try TestEngine.Init();
    defer test_engine.Deinit();
    const engine_context = test_engine.mEngineContext;
    const panel = &test_engine.mPanel;

    //closed, nothing is built
    try panel.Update(engine_context);
    try std.testing.expect(panel.mTree == null);

    try panel.Toggle(engine_context);
    try panel.Update(engine_context);
    try std.testing.expect(panel.mTree != null);
    try std.testing.expectEqual(@as(usize, 1), panel.mBuilt.items.len);
    try std.testing.expectEqualStrings("Master", TextOf(panel.mTitles.items[0]));

    //Volume, Paused and the buttons, and only Add Child
    var rows: [8]Entity = undefined;
    try std.testing.expectEqual(@as(usize, 3), Children(ContentOf(panel.mTitles.items[0]), &rows));
    try std.testing.expectEqual(@as(usize, 1), panel.mButtons.items.len);
    const action = panel.ActionOf(panel.mButtons.items[0].Button).?;
    try std.testing.expectEqual(test_engine.Master().mID, action.AddChild.mID);
    //and nothing else is a button of the panel
    try std.testing.expect(panel.ActionOf(rows[0]) == null);
}

test "adding a bus builds the tree again, with the new bus under its parent" {
    const test_engine = try TestEngine.Init();
    defer test_engine.Deinit();
    const engine_context = test_engine.mEngineContext;
    const panel = &test_engine.mPanel;
    try panel.Toggle(engine_context);
    try panel.Update(engine_context);
    const old_tree = panel.mTree.?;

    try AudioBusesPanel.Run(engine_context, panel.ActionOf(panel.mButtons.items[0].Button).?);
    try panel.Update(engine_context);
    //the old tree hidden until it is deleted at the end of the frame
    try std.testing.expect(old_tree.GetComponent(LayoutItemComponent).?.mCollapsed);
    try std.testing.expect(panel.mTree.?.mID != old_tree.mID);
    try std.testing.expectEqual(@as(usize, 2), panel.mBuilt.items.len);
    try std.testing.expectEqualStrings("Bus", TextOf(panel.mTitles.items[1]));

    //the new bus: Name, Volume, Paused and the buttons, with a Delete for it
    var rows: [8]Entity = undefined;
    try std.testing.expectEqual(@as(usize, 4), Children(ContentOf(panel.mTitles.items[1]), &rows));
    try std.testing.expectEqual(@as(usize, 3), panel.mButtons.items.len);
    try std.testing.expectEqual(panel.mBuilt.items[1], panel.ActionOf(panel.mButtons.items[2].Button).?.Delete.mID);

    //nothing changed, nothing built again
    const tree = panel.mTree.?;
    try panel.Update(engine_context);
    try std.testing.expectEqual(tree.mID, panel.mTree.?.mID);
}

test "a volume edit is written into the bus, and a renamed bus's node follows its name" {
    const test_engine = try TestEngine.Init();
    defer test_engine.Deinit();
    const engine_context = test_engine.mEngineContext;
    const panel = &test_engine.mPanel;
    const child = try test_engine.Master().CreateChild(engine_context, .Entity, Bus.DefaultConfig);
    try panel.Toggle(engine_context);
    try panel.Update(engine_context);

    //Master's Volume, edited the way the number field edits it
    var rows: [8]Entity = undefined;
    _ = Children(ContentOf(panel.mTitles.items[0]), &rows);
    const volume = WidgetOf(rows[0]);
    volume.GetComponent(AttribComponent).?.mData.SetFromFloat(0.25);
    try engine_context.mUIManager.SendToChain(engine_context, volume, .ValueChanged);
    try engine_context.mUIManager.ProcessUIEvents(engine_context, .{});
    try std.testing.expectEqual(@as(f32, 0.25), test_engine.Master().GetComponent(VolumeComponent).?.mVolume);

    const name = child.GetComponent(NameComponent).?;
    name.mName.clearRetainingCapacity();
    try name.mName.appendSlice(engine_context.EngineAllocator(), "Music");
    try panel.Update(engine_context);
    try std.testing.expectEqualStrings("Music", TextOf(panel.mTitles.items[1]));
}
