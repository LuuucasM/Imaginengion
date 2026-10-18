//! Integration tests for the ECS: entity lifetime, hierarchy, queries, deferred events and duplication.
//! These drive a real ECSManager built from the test components below, so they do not depend on the
//! engine's component lists. Run with `zig build test`.
const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const ECS = @import("../../ECS/ECSManager.zig");
const EventResult = @import("../../Events/EventManager.zig").EventResult;

const Position = struct {
    pub const Name: []const u8 = "Position";
    pub const Ind: usize = ECS.BuiltinComponentCount;

    x: f32 = 0,

    pub fn Deinit(_: *Position, _: *EngineContext) void {}
};

/// owns memory, so it has a Clone for DuplicateEntity to use
const Label = struct {
    pub const Name: []const u8 = "Label";
    pub const Ind: usize = ECS.BuiltinComponentCount + 1;

    mText: std.ArrayList(u8) = .empty,

    pub fn Deinit(self: *Label, engine_context: *EngineContext) void {
        self.mText.deinit(engine_context.EngineAllocator());
    }

    pub fn Clone(self: *const Label, engine_context: *EngineContext) !Label {
        return .{ .mText = try self.mText.clone(engine_context.EngineAllocator()) };
    }
};

const Health = struct {
    pub const Name: []const u8 = "Health";
    pub const Ind: usize = ECS.BuiltinComponentCount + 2;

    mHP: u32 = 100,

    pub fn Deinit(_: *Health, _: *EngineContext) void {}
};

const TestComponentsList = [_]type{ Position, Label, Health };
/// What the staging tests lock (ECSManager.Lock), so that their adds are staged
const StagedTypes: []const type = &TestComponentsList;
const TestECSManager = ECS.ECSManager(u32, &TestComponentsList, "TestECS");

const NullEntity = std.math.maxInt(u32);

/// An ECS plus the minimal EngineContext it needs. The context is not Init'd, which would bring up the
/// window and the rest of the engine: the ECS only ever asks it for the engine allocator.
const TestECS = struct {
    mEngineContext: *EngineContext,
    mECSManager: TestECSManager,

    fn Init() !*TestECS {
        const self = try std.heap.page_allocator.create(TestECS);
        self.* = .{
            .mEngineContext = try std.heap.page_allocator.create(EngineContext),
            .mECSManager = .empty,
        };
        self.mEngineContext.* = .{};

        try self.mECSManager.Init(self.mEngineContext.EngineAllocator());

        return self;
    }

    fn Deinit(self: *TestECS) !void {
        const engine_context = self.mEngineContext;

        self.mECSManager.Deinit(engine_context);

        const leak_check = engine_context._Internal.EngineGPA.deinit();

        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);

        try std.testing.expect(leak_check == .ok);
    }

    fn Allocator(self: *TestECS) std.mem.Allocator {
        return self.mEngineContext.EngineAllocator();
    }

    /// end of frame: drains whatever is still queued (see ECSManager.Lock)
    fn ProcessEvents(self: *TestECS) !void {
        try self.mECSManager.ProcessEvents(self.mEngineContext);
    }
};

test "RemoveComponentSync takes the component off before it returns" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const entity_id = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, entity_id, Health{});
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, entity_id, Position{ .x = 3 });

    //the deferred path leaves it readable until ProcessEvents, which is what the sync path exists
    //to avoid: TransformDirtyTag has to be gone before the next transform pass in the same frame
    try test_ecs.mECSManager.RemoveComponentSync(test_ecs.mEngineContext, entity_id, Health.Ind);
    try std.testing.expect(!test_ecs.mECSManager.HasComponent(Health, entity_id));

    //the entity and its other components are untouched
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(entity_id));
    try std.testing.expectEqual(@as(f32, 3), test_ecs.mECSManager.GetComponent(Position, entity_id).?.x);

    //nothing was queued, so end of frame has nothing left to apply
    try test_ecs.ProcessEvents();
    try std.testing.expect(!test_ecs.mECSManager.HasComponent(Health, entity_id));
    try std.testing.expect(test_ecs.mECSManager.HasComponent(Position, entity_id));

    //and it can go back on, which is the add/clear/add cycle a dirty tag goes through across passes
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, entity_id, Health{});
    try std.testing.expect(test_ecs.mECSManager.HasComponent(Health, entity_id));
    try test_ecs.mECSManager.RemoveComponentSync(test_ecs.mEngineContext, entity_id, Health.Ind);
    try std.testing.expect(!test_ecs.mECSManager.HasComponent(Health, entity_id));
}

test "a sync removal and a queued removal of the same component do not collide" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const entity_id = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, entity_id, Health{});

    try test_ecs.mECSManager.RemoveComponent(test_ecs.mEngineContext, entity_id, Health.Ind);
    try test_ecs.mECSManager.RemoveComponentSync(test_ecs.mEngineContext, entity_id, Health.Ind);
    try std.testing.expect(!test_ecs.mECSManager.HasComponent(Health, entity_id));

    //the queued one still fires at end of frame and has to find the component already gone
    try test_ecs.ProcessEvents();
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(entity_id));
}

test "ECS create, add components and query groups" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const entity_1 = try test_ecs.mECSManager.CreateEntity(allocator);
    const entity_2 = try test_ecs.mECSManager.CreateEntity(allocator);

    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, entity_1, Position{ .x = 5 });
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, entity_1, try MakeLabel(test_ecs, "player"));
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, entity_2, Position{ .x = 9 });

    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(entity_1));
    try std.testing.expect(test_ecs.mECSManager.HasComponent(Position, entity_1));
    try std.testing.expect(!test_ecs.mECSManager.HasComponent(Health, entity_1));
    try std.testing.expectEqual(@as(f32, 9), test_ecs.mECSManager.GetComponent(Position, entity_2).?.x);
    try std.testing.expectEqualStrings("player", test_ecs.mECSManager.GetComponent(Label, entity_1).?.mText.items);

    var all_entities = try test_ecs.mECSManager.GetAllEntities(allocator);
    defer all_entities.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), all_entities.items.len);

    var with_label = try test_ecs.mECSManager.GetGroup(allocator, .{ .Component = Label });
    defer with_label.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), with_label.items.len);
    try std.testing.expectEqual(entity_1, with_label.items[0]);

    var with_both = try test_ecs.mECSManager.GetGroup(allocator, .{ .And = &.{ .{ .Component = Position }, .{ .Component = Label } } });
    defer with_both.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), with_both.items.len);

    const position_query = ECS.GroupQuery{ .Component = Position };
    const label_query = ECS.GroupQuery{ .Component = Label };
    var position_without_label = try test_ecs.mECSManager.GetGroup(allocator, .{ .Not = .{ .mFirst = &position_query, .mSecond = &label_query } });
    defer position_without_label.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), position_without_label.items.len);
    try std.testing.expectEqual(entity_2, position_without_label.items[0]);
}

/// The group has exactly `expected`, in any order, each once
fn ExpectGroup(group: std.ArrayList(u32), expected: []const u32) !void {
    try std.testing.expectEqual(expected.len, group.items.len);
    for (expected) |entity_id| {
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u32, group.items, &.{entity_id}));
    }
}

test "ECS entity list difference, union and intersection" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    const a = try ecs.CreateEntity(allocator);
    const b = try ecs.CreateEntity(allocator);
    const c = try ecs.CreateEntity(allocator);
    const d = try ecs.CreateEntity(allocator);

    var list2: std.ArrayList(u32) = .empty;
    defer list2.deinit(allocator);
    try list2.appendSlice(allocator, &.{ b, c, c, d });

    var difference: std.ArrayList(u32) = .empty;
    defer difference.deinit(allocator);
    try difference.appendSlice(allocator, &.{ a, b, c });
    try ecs.EntityListDifference(&difference, list2, allocator);
    try ExpectGroup(difference, &.{a});

    // the repeat of c inside list2 is only added once
    var union_list: std.ArrayList(u32) = .empty;
    defer union_list.deinit(allocator);
    try union_list.appendSlice(allocator, &.{ a, b });
    try ecs.EntityListUnion(&union_list, list2, allocator);
    try ExpectGroup(union_list, &.{ a, b, c, d });

    var intersection: std.ArrayList(u32) = .empty;
    defer intersection.deinit(allocator);
    try intersection.appendSlice(allocator, &.{ a, b, c });
    try ecs.EntityListIntersection(&intersection, list2, allocator);
    try ExpectGroup(intersection, &.{ b, c });

    // an id whose index was reused by a newer entity is not the same entity
    try ecs.DestroyEntity(test_ecs.mEngineContext, d);
    try test_ecs.ProcessEvents();
    const new_d = try ecs.CreateEntity(allocator);
    try std.testing.expect(new_d != d);

    var stale: std.ArrayList(u32) = .empty;
    defer stale.deinit(allocator);
    try stale.append(allocator, new_d);
    try ecs.EntityListIntersection(&stale, list2, allocator);
    try ExpectGroup(stale, &.{});
}

test "ECS compound queries walk the right lists and give each match once" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    // p: Position only, h: Health only, ph: both, phl: all three, none: no components
    const p = try ecs.CreateEntity(allocator);
    const h = try ecs.CreateEntity(allocator);
    const ph = try ecs.CreateEntity(allocator);
    const phl = try ecs.CreateEntity(allocator);
    _ = try ecs.CreateEntity(allocator);

    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, p, Position{});
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, h, Health{});
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, ph, Position{});
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, ph, Health{});
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, phl, Position{});
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, phl, Health{});
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, phl, try MakeLabel(test_ecs, "all"));

    const position_query = ECS.GroupQuery{ .Component = Position };
    const health_query = ECS.GroupQuery{ .Component = Health };
    const label_query = ECS.GroupQuery{ .Component = Label };

    // entities in both lists come up once
    var either = try ecs.GetGroup(allocator, .{ .Or = &.{ position_query, health_query } });
    defer either.deinit(allocator);
    try ExpectGroup(either, &.{ p, h, ph, phl });

    // the same list on both sides is only walked once
    var either_same = try ecs.GetGroup(allocator, .{ .Or = &.{ position_query, .{ .And = &.{ position_query, health_query } } } });
    defer either_same.deinit(allocator);
    try ExpectGroup(either_same, &.{ p, ph, phl });

    // walks Label's list, the shortest, whichever side it is on
    var all_three = try ecs.GetGroup(allocator, .{ .And = &.{ position_query, health_query, label_query } });
    defer all_three.deinit(allocator);
    try ExpectGroup(all_three, &.{phl});

    // not (Health and Label) still lets Health-only and Label-only through
    const health_and_label = ECS.GroupQuery{ .And = &.{ health_query, label_query } };
    var not_both = try ecs.GetGroup(allocator, .{ .Not = .{ .mFirst = &position_query, .mSecond = &health_and_label } });
    defer not_both.deinit(allocator);
    try ExpectGroup(not_both, &.{ p, ph });

    // not (Health or Label) drops anything with either
    const health_or_label = ECS.GroupQuery{ .Or = &.{ health_query, label_query } };
    var neither = try ecs.GetGroup(allocator, .{ .Not = .{ .mFirst = &position_query, .mSecond = &health_or_label } });
    defer neither.deinit(allocator);
    try ExpectGroup(neither, &.{p});

    // an And with an Or side: the Or's lists (Health) against Label's, Label being fewer
    var label_and_either = try ecs.GetGroup(allocator, .{ .And = &.{ health_or_label, label_query } });
    defer label_and_either.deinit(allocator);
    try ExpectGroup(label_and_either, &.{phl});

    // nothing has every component in an empty list
    try ecs.RemoveComponentSync(test_ecs.mEngineContext, phl, Label.Ind);
    var none_left = try ecs.GetGroup(allocator, .{ .And = &.{ position_query, label_query } });
    defer none_left.deinit(allocator);
    try ExpectGroup(none_left, &.{});
}

test "ECS destroy is right away, and waits while a type it has is locked" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const entity_id = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, entity_id, try MakeLabel(test_ecs, "doomed"));
    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, entity_id);
    try std.testing.expect(!test_ecs.mECSManager.IsActiveEntity(entity_id));

    const locked_id = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, locked_id, try MakeLabel(test_ecs, "locked"));
    test_ecs.mECSManager.Lock(&.{Label});
    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, locked_id);
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(locked_id)); //still readable while locked
    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, &.{Label});
    try std.testing.expect(!test_ecs.mECSManager.IsActiveEntity(locked_id));
}

test "ECS destroy takes the whole subtree" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const root = try test_ecs.mECSManager.CreateEntity(allocator);
    const child_1 = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Entity);
    const child_2 = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Entity);
    const script = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Script);
    const grandchild = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, child_1, .Entity);

    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, grandchild, try MakeLabel(test_ecs, "deep"));

    try std.testing.expectEqual(root, test_ecs.mECSManager.GetComponent(TestECSManager.ChildComponent, child_1).?.mParent);
    try std.testing.expectEqual(child_2, test_ecs.mECSManager.GetComponent(TestECSManager.ChildComponent, child_1).?.mNext);

    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, root);
    try test_ecs.ProcessEvents();

    for ([_]u32{ root, child_1, child_2, script, grandchild }) |entity_id| {
        try std.testing.expect(!test_ecs.mECSManager.IsActiveEntity(entity_id));
    }
}

test "ECS destroying one child keeps the list and mFirst valid" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const root = try test_ecs.mECSManager.CreateEntity(allocator);
    const child_1 = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Entity);
    const child_2 = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Entity);
    const child_3 = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Entity);

    //destroying the head of the list is the case that has to move mFirstEntity and every mFirst
    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, child_1);
    try test_ecs.ProcessEvents();

    try std.testing.expect(!test_ecs.mECSManager.IsActiveEntity(child_1));
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(child_2));
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(child_3));

    const parent_component = test_ecs.mECSManager.GetComponent(TestECSManager.ParentComponent, root).?;
    try std.testing.expectEqual(child_2, parent_component.mFirstEntity);

    const child_2_component = test_ecs.mECSManager.GetComponent(TestECSManager.ChildComponent, child_2).?;
    const child_3_component = test_ecs.mECSManager.GetComponent(TestECSManager.ChildComponent, child_3).?;
    try std.testing.expectEqual(child_3, child_2_component.mNext);
    try std.testing.expectEqual(child_2, child_3_component.mNext);
    try std.testing.expectEqual(child_3, child_2_component.mPrev);
    try std.testing.expectEqual(child_2, child_2_component.mFirst);
    try std.testing.expectEqual(child_2, child_3_component.mFirst);

    //emptying both lists drops the ParentComponent
    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, child_2);
    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, child_3);
    try test_ecs.ProcessEvents();
    try std.testing.expect(!test_ecs.mECSManager.HasComponent(TestECSManager.ParentComponent, root));
}

test "ECS scripts and entities are separate child lists" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const root = try test_ecs.mECSManager.CreateEntity(allocator);
    const child = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Entity);
    const script = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Script);

    const parent_component = test_ecs.mECSManager.GetComponent(TestECSManager.ParentComponent, root).?;
    try std.testing.expectEqual(child, parent_component.mFirstEntity);
    try std.testing.expectEqual(script, parent_component.mFirstScript);

    //removing the script must leave the entity list alone
    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, script);
    try test_ecs.ProcessEvents();

    const after_component = test_ecs.mECSManager.GetComponent(TestECSManager.ParentComponent, root).?;
    try std.testing.expectEqual(child, after_component.mFirstEntity);
    try std.testing.expectEqual(NullEntity, after_component.mFirstScript);
}

test "ECS recycles destroyed ids with a new generation" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const entity_1 = try test_ecs.mECSManager.CreateEntity(allocator);
    const entity_2 = try test_ecs.mECSManager.CreateEntity(allocator);
    const entity_3 = try test_ecs.mECSManager.CreateEntity(allocator);

    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, entity_1);
    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, entity_3);
    try test_ecs.ProcessEvents();

    const reused_1 = try test_ecs.mECSManager.CreateEntity(allocator);
    const reused_2 = try test_ecs.mECSManager.CreateEntity(allocator);

    try std.testing.expect(reused_1 != reused_2);
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(entity_2));
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(reused_1));
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(reused_2));

    //the old handles stay dead because the generation moved on
    try std.testing.expect(!test_ecs.mECSManager.IsActiveEntity(entity_1));
    try std.testing.expect(!test_ecs.mECSManager.IsActiveEntity(entity_3));

    const index_mask: u32 = (1 << 20) - 1;
    try std.testing.expectEqual(entity_3 & index_mask, reused_1 & index_mask); //newest freed id first
    try std.testing.expectEqual(@as(u32, 1), reused_1 >> 20);
}

test "ECS a destroy waits when something under the entity has a locked type" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    //only the grandchild has the locked type
    const root = try ecs.CreateEntity(allocator);
    const child = try ecs.AddChild(test_ecs.mEngineContext, root, .Entity);
    const grandchild = try ecs.AddChild(test_ecs.mEngineContext, child, .Script);
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, grandchild, Health{});

    ecs.Lock(&.{Health});
    try ecs.DestroyEntity(test_ecs.mEngineContext, root);
    try std.testing.expect(ecs.IsActiveEntity(root));
    try std.testing.expect(ecs.IsActiveEntity(grandchild));

    //an entity with nothing locked under it still goes right away, after the queued one
    const unrelated = try ecs.CreateEntity(allocator);
    try ecs.DestroyEntity(test_ecs.mEngineContext, unrelated);
    try std.testing.expect(ecs.IsActiveEntity(unrelated)); //queued behind the root's, to keep the order

    try ecs.Unlock(test_ecs.mEngineContext, &.{Health});
    try std.testing.expect(!ecs.IsActiveEntity(root));
    try std.testing.expect(!ecs.IsActiveEntity(child));
    try std.testing.expect(!ecs.IsActiveEntity(grandchild));
    try std.testing.expect(!ecs.IsActiveEntity(unrelated));
}

test "ECS remove component is right away, and queued ones survive duplicates" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    const entity_id = try ecs.CreateEntity(allocator);
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, entity_id, try MakeLabel(test_ecs, "temp"));
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, entity_id, Health{});

    try ecs.RemoveComponent(test_ecs.mEngineContext, entity_id, Label.Ind);
    try std.testing.expect(!ecs.HasComponent(Label, entity_id));
    //a second removal of what is gone does nothing
    try ecs.RemoveComponent(test_ecs.mEngineContext, entity_id, Label.Ind);
    try std.testing.expect(ecs.HasComponent(Health, entity_id));

    //queued twice while locked, then a destroy of the same entity behind them
    ecs.Lock(&.{Health});
    try ecs.RemoveComponent(test_ecs.mEngineContext, entity_id, Health.Ind);
    try ecs.RemoveComponent(test_ecs.mEngineContext, entity_id, Health.Ind);
    try ecs.DestroyEntity(test_ecs.mEngineContext, entity_id);
    try std.testing.expect(ecs.HasComponent(Health, entity_id));
    try ecs.Unlock(test_ecs.mEngineContext, &.{Health});
    try std.testing.expect(!ecs.IsActiveEntity(entity_id));
}

test "ECS duplicate copies components, clones owned memory and copies the subtree" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const root = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, root, Position{ .x = 3 });
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, root, try MakeLabel(test_ecs, "original"));

    const child = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Entity);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, child, try MakeLabel(test_ecs, "child"));
    const script = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Script);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, script, Health{ .mHP = 7 });

    const copy = try test_ecs.mECSManager.DuplicateEntity(test_ecs.mEngineContext, root);
    try test_ecs.ProcessEvents(); //lands the staged copies

    try std.testing.expect(copy != root);
    try std.testing.expectEqual(@as(f32, 3), test_ecs.mECSManager.GetComponent(Position, copy).?.x);

    //the label is a real copy rather than a second pointer to the same memory
    const original_label = test_ecs.mECSManager.GetComponent(Label, root).?;
    const copied_label = test_ecs.mECSManager.GetComponent(Label, copy).?;
    try std.testing.expectEqualStrings("original", copied_label.mText.items);
    try std.testing.expect(original_label.mText.items.ptr != copied_label.mText.items.ptr);

    //the copy is a root like the original, with its own children
    try std.testing.expect(!test_ecs.mECSManager.HasComponent(TestECSManager.ChildComponent, copy));
    const copy_parent_component = test_ecs.mECSManager.GetComponent(TestECSManager.ParentComponent, copy).?;
    const copied_child = copy_parent_component.mFirstEntity;
    const copied_script = copy_parent_component.mFirstScript;
    try std.testing.expect(copied_child != NullEntity and copied_child != child);
    try std.testing.expect(copied_script != NullEntity and copied_script != script);
    try std.testing.expectEqualStrings("child", test_ecs.mECSManager.GetComponent(Label, copied_child).?.mText.items);
    try std.testing.expectEqual(@as(u32, 7), test_ecs.mECSManager.GetComponent(Health, copied_script).?.mHP);
    try std.testing.expectEqual(copy, test_ecs.mECSManager.GetComponent(TestECSManager.ChildComponent, copied_child).?.mParent);

    //destroying the original leaves the copy untouched
    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, root);
    try test_ecs.ProcessEvents();
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(copy));
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(copied_child));
    try std.testing.expectEqualStrings("original", test_ecs.mECSManager.GetComponent(Label, copy).?.mText.items);
}

test "ECS duplicating a child joins the same parent" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const root = try test_ecs.mECSManager.CreateEntity(allocator);
    const child = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Entity);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, child, Position{ .x = 1 });

    const copy = try test_ecs.mECSManager.DuplicateEntity(test_ecs.mEngineContext, child);
    try test_ecs.ProcessEvents(); //lands the staged copy

    const copy_child_component = test_ecs.mECSManager.GetComponent(TestECSManager.ChildComponent, copy).?;
    try std.testing.expectEqual(root, copy_child_component.mParent);
    try std.testing.expectEqual(child, test_ecs.mECSManager.GetComponent(TestECSManager.ParentComponent, root).?.mFirstEntity);
    try std.testing.expectEqual(@as(f32, 1), test_ecs.mECSManager.GetComponent(Position, copy).?.x);
}

test "ECS clearAndFree empties everything and drops queued events" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const entity_id = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, entity_id, try MakeLabel(test_ecs, "gone"));
    _ = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, entity_id, .Entity);
    //a staged add that owns memory, which the clear has to deinit since it never reaches its entity
    const staged_entity = try test_ecs.mECSManager.CreateEntity(allocator);
    test_ecs.mECSManager.Lock(StagedTypes); //their adds are staged until the Unlock
    _ = try test_ecs.mECSManager.AddComponent(test_ecs.mEngineContext, staged_entity, try MakeLabel(test_ecs, "staged"));
    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, entity_id); //leave an event queued too

    test_ecs.mECSManager.clearAndFree(test_ecs.mEngineContext);
    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, StagedTypes);

    try std.testing.expect(!test_ecs.mECSManager.IsActiveEntity(entity_id));

    const fresh_entity = try test_ecs.mECSManager.CreateEntity(allocator);
    try std.testing.expectEqual(@as(u32, 0), fresh_entity); //ids start over
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(fresh_entity));

    //the destroy queued before the clear must not fire against the new entity
    try test_ecs.ProcessEvents();
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(fresh_entity));
}

test "ECS copy is a deep copy that keeps every id" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const engine_context = test_ecs.mEngineContext;

    const root = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, root, Position{ .x = 4 });
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, root, try MakeLabel(test_ecs, "root"));

    const child = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Entity);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, child, try MakeLabel(test_ecs, "child"));
    const script = try test_ecs.mECSManager.AddChild(test_ecs.mEngineContext, root, .Script);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, script, Health{ .mHP = 7 });

    //a destroyed id, so the free list has something in it to carry over
    const recycled = try test_ecs.mECSManager.CreateEntity(allocator);
    try test_ecs.mECSManager.DestroyEntity(engine_context, recycled);
    try test_ecs.ProcessEvents();

    const other = try OtherECS.Init(test_ecs);
    defer other.Deinit(test_ecs);

    try test_ecs.mECSManager.Copy(engine_context, other.mECSManager);

    //the same entities under the same ids
    try std.testing.expect(other.mECSManager.IsActiveEntity(root));
    try std.testing.expect(other.mECSManager.IsActiveEntity(child));
    try std.testing.expect(other.mECSManager.IsActiveEntity(script));
    try std.testing.expect(!other.mECSManager.IsActiveEntity(recycled));
    try std.testing.expectEqual(@as(f32, 4), other.mECSManager.GetComponent(Position, root).?.x);
    try std.testing.expectEqual(@as(u32, 7), other.mECSManager.GetComponent(Health, script).?.mHP);

    //the hierarchy came with them
    const other_parent = other.mECSManager.GetComponent(TestECSManager.ParentComponent, root).?;
    try std.testing.expectEqual(child, other_parent.mFirstEntity);
    try std.testing.expectEqual(script, other_parent.mFirstScript);
    try std.testing.expectEqual(root, other.mECSManager.GetComponent(TestECSManager.ChildComponent, child).?.mParent);

    //owned memory is cloned rather than shared
    const original_label = test_ecs.mECSManager.GetComponent(Label, root).?;
    const copied_label = other.mECSManager.GetComponent(Label, root).?;
    try std.testing.expectEqualStrings("root", copied_label.mText.items);
    try std.testing.expect(original_label.mText.items.ptr != copied_label.mText.items.ptr);

    //both sides hand out the same next id, recycling the same freed one first
    const next_original = try test_ecs.mECSManager.CreateEntity(allocator);
    const next_copy = try other.mECSManager.CreateEntity(allocator);
    try std.testing.expectEqual(next_original, next_copy);
    try std.testing.expectEqual(recycled & ((1 << 20) - 1), next_copy & ((1 << 20) - 1));

    //and the two go their own way from here on
    try test_ecs.mECSManager.DestroyEntity(engine_context, root);
    try test_ecs.ProcessEvents();
    try std.testing.expect(!test_ecs.mECSManager.IsActiveEntity(root));
    try std.testing.expect(other.mECSManager.IsActiveEntity(root));
    try std.testing.expectEqualStrings("root", other.mECSManager.GetComponent(Label, root).?.mText.items);
}

test "ECS copy carries the queued events" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const engine_context = test_ecs.mEngineContext;

    const entity_id = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponentSync(test_ecs.mEngineContext, entity_id, try MakeLabel(test_ecs, "doomed"));
    test_ecs.mECSManager.Lock(&.{Label});
    try test_ecs.mECSManager.DestroyEntity(engine_context, entity_id); //queued, the label being locked

    const other = try OtherECS.Init(test_ecs);
    defer other.Deinit(test_ecs);

    try test_ecs.mECSManager.Copy(engine_context, other.mECSManager);

    //the destroy came across still queued, and applies to the copy's own entity
    try std.testing.expect(other.mECSManager.IsActiveEntity(entity_id));
    try other.mECSManager.ProcessEvents(engine_context);
    try std.testing.expect(!other.mECSManager.IsActiveEntity(entity_id));
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(entity_id));

    try test_ecs.mECSManager.Unlock(engine_context, &.{Label});
    try std.testing.expect(!test_ecs.mECSManager.IsActiveEntity(entity_id));
}

test "ECS a staged component reads as on its entity, but queries wait for ProcessEvents" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    const entity_id = try ecs.CreateEntity(allocator);
    test_ecs.mECSManager.Lock(StagedTypes); //their adds are staged until the Unlock
    const staged_position = try ecs.AddComponent(test_ecs.mEngineContext, entity_id, Position{ .x = 1 });
    _ = try ecs.AddComponent(test_ecs.mEngineContext, entity_id, try MakeLabel(test_ecs, "staged"));
    _ = try ecs.AddComponent(test_ecs.mEngineContext, entity_id, ECS.MainObjectComponent{}); //zero sized

    //the returned pointer is the staged copy, which can still be filled in this frame
    staged_position.x = 5;

    //Get and Has find the staged copies, and writes through GetComponent go into them too
    try std.testing.expect(ecs.HasComponent(Position, entity_id));
    try std.testing.expect(ecs.HasComponentInd(Label.Ind, entity_id));
    try std.testing.expectEqual(staged_position, ecs.GetComponent(Position, entity_id).?);
    try ecs.GetComponent(Label, entity_id).?.mText.appendSlice(allocator, " and written");

    //queries only see what is in the arrays: not the staged data, but the tag, which went on right away
    var with_position = try ecs.GetGroup(allocator, .{ .Component = Position });
    try ExpectGroup(with_position, &.{});
    with_position.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), ecs.NumWithComponent(Label));
    var main_objects = try ecs.GetGroup(allocator, .{ .Component = ECS.MainObjectComponent });
    try ExpectGroup(main_objects, &.{entity_id});
    main_objects.deinit(allocator);

    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, StagedTypes);
    try test_ecs.ProcessEvents();

    //what was written through either pointer is what landed
    try std.testing.expectEqual(@as(f32, 5), ecs.GetComponent(Position, entity_id).?.x);
    try std.testing.expect(ecs.GetComponent(Position, entity_id).? != staged_position);
    try std.testing.expectEqualStrings("staged and written", ecs.GetComponent(Label, entity_id).?.mText.items);
    with_position = try ecs.GetGroup(allocator, .{ .Component = Position });
    defer with_position.deinit(allocator);
    try ExpectGroup(with_position, &.{entity_id});
}

test "ECS staged adds don't move components already in the array" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    const first = try ecs.CreateEntity(allocator);
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, first, Position{ .x = 2 });
    const held_position = ecs.GetComponent(Position, first).?;

    test_ecs.mECSManager.Lock(StagedTypes); //their adds are staged until the Unlock
    //plenty of adds to the same array, which would have grown it and moved held_position had they been immediate
    for (0..256) |i| {
        const entity_id = try ecs.CreateEntity(allocator);
        _ = try ecs.AddComponent(test_ecs.mEngineContext, entity_id, Position{ .x = @floatFromInt(i) });
    }

    try std.testing.expectEqual(held_position, ecs.GetComponent(Position, first).?);
    try std.testing.expectEqual(@as(f32, 2), held_position.x);

    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, StagedTypes);
    try test_ecs.ProcessEvents();
    try std.testing.expectEqual(@as(usize, 257), ecs.NumWithComponent(Position));
}

test "ECS a staged add and a destroy in one frame clean up in either order" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    test_ecs.mECSManager.Lock(StagedTypes); //their adds are staged until the Unlock
    //added then destroyed: the add lands and the destroy takes it off again
    const add_first = try ecs.CreateEntity(allocator);
    _ = try ecs.AddComponent(test_ecs.mEngineContext, add_first, try MakeLabel(test_ecs, "added first"));
    try ecs.DestroyEntity(test_ecs.mEngineContext, add_first);

    //destroyed then added: the add finds the entity gone and deinits its staged component
    const destroy_first = try ecs.CreateEntity(allocator);
    try ecs.DestroyEntity(test_ecs.mEngineContext, destroy_first);
    _ = try ecs.AddComponent(test_ecs.mEngineContext, destroy_first, try MakeLabel(test_ecs, "destroyed first"));

    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, StagedTypes);
    try test_ecs.ProcessEvents();

    //the leak check in Deinit is what shows both labels were freed exactly once
    try std.testing.expect(!ecs.IsActiveEntity(add_first));
    try std.testing.expect(!ecs.IsActiveEntity(destroy_first));
    try std.testing.expectEqual(@as(usize, 0), ecs.NumWithComponent(Label));
}

test "ECS queued removes and adds of one component apply in order" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    //remove then add: the add used to hit the "already has it" assert, the removal not having happened yet
    const swapped = try ecs.CreateEntity(allocator);
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, swapped, Health{ .mHP = 100 });
    test_ecs.mECSManager.Lock(StagedTypes); //their adds are staged until the Unlock
    try ecs.RemoveComponent(test_ecs.mEngineContext, swapped, Health.Ind);
    _ = try ecs.AddComponent(test_ecs.mEngineContext, swapped, Health{ .mHP = 7 });

    //add then remove: never seen by anyone
    const brief = try ecs.CreateEntity(allocator);
    _ = try ecs.AddComponent(test_ecs.mEngineContext, brief, try MakeLabel(test_ecs, "brief"));
    try ecs.RemoveComponent(test_ecs.mEngineContext, brief, Label.Ind);

    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, StagedTypes);
    try test_ecs.ProcessEvents();

    try std.testing.expectEqual(@as(u32, 7), ecs.GetComponent(Health, swapped).?.mHP);
    try std.testing.expect(!ecs.HasComponent(Label, brief));
}

test "ECS a tag goes on right away and shows in queries" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    const entity_id = try ecs.CreateEntity(allocator);
    _ = try ecs.AddComponent(test_ecs.mEngineContext, entity_id, ECS.MainObjectComponent{});

    try std.testing.expectEqual(@as(usize, 1), ecs.NumWithComponent(ECS.MainObjectComponent));
    //nothing was staged for it
    try test_ecs.ProcessEvents();
    try std.testing.expectEqual(@as(usize, 1), ecs.NumWithComponent(ECS.MainObjectComponent));
}

test "ECS RemoveComponentSync takes a staged component back off the stage" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    const entity_id = try ecs.CreateEntity(allocator);
    test_ecs.mECSManager.Lock(StagedTypes); //their adds are staged until the Unlock
    _ = try ecs.AddComponent(test_ecs.mEngineContext, entity_id, try MakeLabel(test_ecs, "first"));
    try ecs.RemoveComponentSync(test_ecs.mEngineContext, entity_id, Label.Ind);
    try std.testing.expect(!ecs.HasComponent(Label, entity_id));

    //staged again under the same entity and slot: the first queued add must not land this one twice
    _ = try ecs.AddComponent(test_ecs.mEngineContext, entity_id, try MakeLabel(test_ecs, "second"));

    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, StagedTypes);
    try test_ecs.ProcessEvents();

    //the leak check in Deinit shows the first label was freed when it came off, and only then
    try std.testing.expectEqualStrings("second", ecs.GetComponent(Label, entity_id).?.mText.items);
    try std.testing.expectEqual(@as(usize, 1), ecs.NumWithComponent(Label));
}

test "ECS DuplicateEntity copies the original's staged components too" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    const root = try ecs.CreateEntity(allocator);
    test_ecs.mECSManager.Lock(StagedTypes); //their adds are staged until the Unlock
    _ = try ecs.AddComponent(test_ecs.mEngineContext, root, try MakeLabel(test_ecs, "staged"));
    _ = try ecs.AddComponent(test_ecs.mEngineContext, root, Position{ .x = 6 });
    _ = try ecs.AddComponent(test_ecs.mEngineContext, root, ECS.MainObjectComponent{});
    //one staged and taken back off, which is no longer part of the original
    _ = try ecs.AddComponent(test_ecs.mEngineContext, root, Health{});
    try ecs.RemoveComponentSync(test_ecs.mEngineContext, root, Health.Ind);

    const copy = try ecs.DuplicateEntity(test_ecs.mEngineContext, root);

    try std.testing.expect(ecs.HasComponent(ECS.MainObjectComponent, copy));
    try std.testing.expectEqualStrings("staged", ecs.GetComponent(Label, copy).?.mText.items);
    try std.testing.expect(ecs.GetComponent(Label, copy).?.mText.items.ptr != ecs.GetComponent(Label, root).?.mText.items.ptr);

    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, StagedTypes);
    try test_ecs.ProcessEvents();

    try std.testing.expectEqual(@as(f32, 6), ecs.GetComponent(Position, copy).?.x);
    try std.testing.expectEqualStrings("staged", ecs.GetComponent(Label, copy).?.mText.items);
    try std.testing.expect(!ecs.HasComponent(Health, copy));
    try std.testing.expectEqual(@as(usize, 2), ecs.NumWithComponent(Label));
}

test "ECS copy only clones adds that are still staged" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const engine_context = test_ecs.mEngineContext;

    const entity_id = try test_ecs.mECSManager.CreateEntity(allocator);
    test_ecs.mECSManager.Lock(StagedTypes); //their adds are staged until the Unlock
    _ = try test_ecs.mECSManager.AddComponent(engine_context, entity_id, try MakeLabel(test_ecs, "taken off"));
    try test_ecs.mECSManager.RemoveComponentSync(engine_context, entity_id, Label.Ind);
    _ = try test_ecs.mECSManager.AddComponent(engine_context, entity_id, Health{ .mHP = 3 });

    const other = try OtherECS.Init(test_ecs);
    defer other.Deinit(test_ecs);
    try test_ecs.mECSManager.Copy(engine_context, other.mECSManager);

    //the copy reads the staged one, and not the one taken off, which was freed and must not be cloned
    try std.testing.expectEqual(@as(u32, 3), other.mECSManager.GetComponent(Health, entity_id).?.mHP);
    try std.testing.expect(!other.mECSManager.HasComponent(Label, entity_id));

    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, StagedTypes);
    try test_ecs.ProcessEvents();
    try other.mECSManager.ProcessEvents(engine_context);

    try std.testing.expectEqual(@as(u32, 3), other.mECSManager.GetComponent(Health, entity_id).?.mHP);
    try std.testing.expect(!other.mECSManager.HasComponent(Label, entity_id));
}

/// Records what the removal hook could read when each kind of removal reached it
const RemovalWatcher = struct {
    mECS: *TestECSManager,
    mRemovals: usize = 0,
    mDestroys: usize = 0,
    mSawComponent: bool = true,

    fn OnRemoval(ctx: *anyopaque, _: *EngineContext, event: TestECSManager.ECSEventDataT.EventT) anyerror!void {
        const self: *RemovalWatcher = @ptrCast(@alignCast(ctx));
        switch (event) {
            .RemoveComponent => |e| {
                self.mRemovals += 1;
                self.mSawComponent = self.mSawComponent and self.mECS.HasComponentInd(e.mComponentInd, e.mEntityID);
            },
            .DestroyEntity => |e| {
                self.mDestroys += 1;
                self.mSawComponent = self.mSawComponent and self.mECS.HasComponent(Health, e.mEntityID);
            },
            else => {},
        }
    }
};

test "ECS the removal hook hears of each removal and destroy while it can still be read" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    var watcher = RemovalWatcher{ .mECS = ecs };
    ecs.SetRemovalHook(.{ .mCtx = &watcher, .mFn = RemovalWatcher.OnRemoval });

    //right away
    const removed_from = try ecs.CreateEntity(allocator);
    _ = try ecs.AddComponent(test_ecs.mEngineContext, removed_from, Health{});
    try ecs.RemoveComponent(test_ecs.mEngineContext, removed_from, Health.Ind);
    try std.testing.expect(!ecs.HasComponent(Health, removed_from));
    try std.testing.expectEqual(@as(usize, 1), watcher.mRemovals);

    //a parent and its child, each told of on its own, the child first
    const parent = try ecs.CreateEntity(allocator);
    _ = try ecs.AddComponent(test_ecs.mEngineContext, parent, Health{});
    const child = try ecs.AddChild(test_ecs.mEngineContext, parent, .Entity);
    _ = try ecs.AddComponent(test_ecs.mEngineContext, child, Health{});
    try ecs.DestroyEntity(test_ecs.mEngineContext, parent);
    try std.testing.expect(!ecs.IsActiveEntity(parent));
    try std.testing.expect(!ecs.IsActiveEntity(child));
    try std.testing.expectEqual(@as(usize, 2), watcher.mDestroys);

    //and a removal that waits for a lock, told of when the queue drains rather than when it was asked for
    const locked = try ecs.CreateEntity(allocator);
    _ = try ecs.AddComponent(test_ecs.mEngineContext, locked, Health{});
    ecs.Lock(&.{Health});
    try ecs.RemoveComponent(test_ecs.mEngineContext, locked, Health.Ind);
    try std.testing.expect(ecs.HasComponent(Health, locked));
    try std.testing.expectEqual(@as(usize, 1), watcher.mRemovals);
    try ecs.Unlock(test_ecs.mEngineContext, &.{Health});
    try std.testing.expect(!ecs.HasComponent(Health, locked));
    try std.testing.expectEqual(@as(usize, 2), watcher.mRemovals);

    try std.testing.expect(watcher.mSawComponent);
}

test "ECS AddChild links the child before it returns" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    const root = try ecs.CreateEntity(allocator);
    const child_1 = try ecs.AddChild(test_ecs.mEngineContext, root, .Entity);
    const child_2 = try ecs.AddChild(test_ecs.mEngineContext, root, .Entity);
    const script = try ecs.AddChild(test_ecs.mEngineContext, root, .Script);
    const grandchild = try ecs.AddChild(test_ecs.mEngineContext, child_1, .Entity);

    //linked in the order they were added, scripts in their own list, with nothing queued
    const parent_component = ecs.GetComponent(TestECSManager.ParentComponent, root).?;
    try std.testing.expectEqual(child_1, parent_component.mFirstEntity);
    try std.testing.expectEqual(script, parent_component.mFirstScript);
    const child_1_component = ecs.GetComponent(TestECSManager.ChildComponent, child_1).?;
    try std.testing.expectEqual(child_2, child_1_component.mNext);
    try std.testing.expectEqual(child_2, child_1_component.mPrev);
    try std.testing.expectEqual(root, child_1_component.mParent);
    try std.testing.expectEqual(child_1, ecs.GetComponent(TestECSManager.ChildComponent, child_2).?.mFirst);
    try std.testing.expectEqual(script, ecs.GetComponent(TestECSManager.ChildComponent, script).?.mNext);
    try std.testing.expectEqual(child_1, ecs.GetComponent(TestECSManager.ChildComponent, grandchild).?.mParent);
    try std.testing.expectEqual(grandchild, ecs.GetComponent(TestECSManager.ParentComponent, child_1).?.mFirstEntity);

    //and in the queries too
    try std.testing.expectEqual(@as(usize, 4), ecs.NumWithComponent(TestECSManager.ChildComponent));

    //nothing left queued to link them a second time
    try test_ecs.ProcessEvents();
    try std.testing.expectEqual(child_2, ecs.GetComponent(TestECSManager.ChildComponent, child_1).?.mNext);
    try std.testing.expectEqual(child_1, ecs.GetComponent(TestECSManager.ChildComponent, child_2).?.mNext);
}

test "ECS a child added under a parent whose destroy waits for a lock goes with it" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    const root = try ecs.CreateEntity(allocator);
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, root, Health{});
    ecs.Lock(&.{Health});
    try ecs.DestroyEntity(test_ecs.mEngineContext, root);
    //the root is still there while its destroy waits, so it can still be given children, which the destroy takes along
    const child = try ecs.AddChild(test_ecs.mEngineContext, root, .Entity);
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, child, try MakeLabel(test_ecs, "orphan"));
    const grandchild = try ecs.AddChild(test_ecs.mEngineContext, child, .Script);

    try ecs.Unlock(test_ecs.mEngineContext, &.{Health});

    try std.testing.expect(!ecs.IsActiveEntity(root));
    try std.testing.expect(!ecs.IsActiveEntity(child));
    try std.testing.expect(!ecs.IsActiveEntity(grandchild));
    try std.testing.expectEqual(@as(usize, 0), ecs.NumWithComponent(Label));
}

test "ECS a child destroyed in the frame it was added leaves its parent as it was" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    const root = try ecs.CreateEntity(allocator);
    const kept = try ecs.AddChild(test_ecs.mEngineContext, root, .Entity);
    const brief = try ecs.AddChild(test_ecs.mEngineContext, root, .Entity);
    try ecs.DestroyEntity(test_ecs.mEngineContext, brief);

    try test_ecs.ProcessEvents();

    try std.testing.expect(!ecs.IsActiveEntity(brief));
    const kept_component = ecs.GetComponent(TestECSManager.ChildComponent, kept).?;
    try std.testing.expectEqual(kept, kept_component.mNext);
    try std.testing.expectEqual(kept, kept_component.mPrev);
    try std.testing.expectEqual(kept, ecs.GetComponent(TestECSManager.ParentComponent, root).?.mFirstEntity);
}

test "ECS DuplicateEntity stages a copy of the original as it is now" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    const root = try ecs.CreateEntity(allocator);
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, root, Position{ .x = 3 });
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, root, try MakeLabel(test_ecs, "original"));
    const child = try ecs.AddChild(test_ecs.mEngineContext, root, .Entity);
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, child, Health{ .mHP = 9 });

    test_ecs.mECSManager.Lock(StagedTypes); //their adds are staged until the Unlock
    const copy = try ecs.DuplicateEntity(test_ecs.mEngineContext, root);

    //the copy reads as having its components straight away, though they are only staged
    try std.testing.expect(ecs.IsActiveEntity(copy));
    try std.testing.expectEqual(@as(f32, 3), ecs.GetComponent(Position, copy).?.x);
    try std.testing.expectEqual(@as(usize, 1), ecs.NumWithComponent(Position));

    //changes to the original after the duplicate don't reach the copy
    ecs.GetComponent(Position, root).?.x = 100;
    try ecs.GetComponent(Label, root).?.mText.appendSlice(allocator, " changed");

    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, StagedTypes);
    try test_ecs.ProcessEvents();

    try std.testing.expectEqual(@as(f32, 3), ecs.GetComponent(Position, copy).?.x);
    try std.testing.expectEqualStrings("original", ecs.GetComponent(Label, copy).?.mText.items);
    const copied_child = ecs.GetComponent(TestECSManager.ParentComponent, copy).?.mFirstEntity;
    try std.testing.expectEqual(@as(u32, 9), ecs.GetComponent(Health, copied_child).?.mHP);
    try std.testing.expectEqual(copy, ecs.GetComponent(TestECSManager.ChildComponent, copied_child).?.mParent);
}

test "ECS a duplicate destroyed in the frame it was made frees its staged copies" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const ecs = &test_ecs.mECSManager;

    const root = try ecs.CreateEntity(allocator);
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, root, try MakeLabel(test_ecs, "original"));
    const child = try ecs.AddChild(test_ecs.mEngineContext, root, .Entity);
    _ = try ecs.AddComponentSync(test_ecs.mEngineContext, child, try MakeLabel(test_ecs, "child"));

    test_ecs.mECSManager.Lock(StagedTypes); //their adds are staged until the Unlock
    const copy = try ecs.DuplicateEntity(test_ecs.mEngineContext, root);
    try ecs.DestroyEntity(test_ecs.mEngineContext, copy);

    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, StagedTypes);
    try test_ecs.ProcessEvents();

    //the leak check in Deinit is what shows the cloned labels were freed
    try std.testing.expect(!ecs.IsActiveEntity(copy));
    try std.testing.expectEqual(@as(usize, 2), ecs.NumWithComponent(Label));
}

test "ECS copy gives queued adds clones of their own" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const engine_context = test_ecs.mEngineContext;

    const entity_id = try test_ecs.mECSManager.CreateEntity(allocator);
    test_ecs.mECSManager.Lock(StagedTypes); //their adds are staged until the Unlock
    const staged_label = try test_ecs.mECSManager.AddComponent(engine_context, entity_id, try MakeLabel(test_ecs, "staged"));
    _ = try test_ecs.mECSManager.AddComponent(engine_context, entity_id, Position{ .x = 4 });

    const other = try OtherECS.Init(test_ecs);
    defer other.Deinit(test_ecs);

    try test_ecs.mECSManager.Copy(engine_context, other.mECSManager);

    //writing through this ECS's staged pointer after the copy only changes this ECS's add
    try staged_label.mText.appendSlice(allocator, " here");

    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, StagedTypes);
    try test_ecs.ProcessEvents();
    try other.mECSManager.ProcessEvents(engine_context);

    const label = test_ecs.mECSManager.GetComponent(Label, entity_id).?;
    const other_label = other.mECSManager.GetComponent(Label, entity_id).?;
    try std.testing.expectEqualStrings("staged here", label.mText.items);
    try std.testing.expectEqualStrings("staged", other_label.mText.items);
    try std.testing.expect(label.mText.items.ptr != other_label.mText.items.ptr);
    try std.testing.expectEqual(@as(f32, 4), other.mECSManager.GetComponent(Position, entity_id).?.x);
}

test "ECS a copy's queued adds are freed if it is torn down before processing them" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();
    const engine_context = test_ecs.mEngineContext;

    const entity_id = try test_ecs.mECSManager.CreateEntity(allocator);
    test_ecs.mECSManager.Lock(StagedTypes); //their adds are staged until the Unlock
    _ = try test_ecs.mECSManager.AddComponent(engine_context, entity_id, try MakeLabel(test_ecs, "staged"));

    const other = try OtherECS.Init(test_ecs);
    try test_ecs.mECSManager.Copy(engine_context, other.mECSManager);
    //torn down with its clone still queued, which only the leak check can see
    other.Deinit(test_ecs);

    try test_ecs.mECSManager.Unlock(test_ecs.mEngineContext, StagedTypes);
    try test_ecs.ProcessEvents();
    try std.testing.expectEqualStrings("staged", test_ecs.mECSManager.GetComponent(Label, entity_id).?.mText.items);
}

/// A second, empty ECS sharing the first one's EngineContext, which is what Copy needs:
/// both sides are allocated and freed through the same engine allocator.
const OtherECS = struct {
    mECSManager: *TestECSManager,

    fn Init(test_ecs: *TestECS) !OtherECS {
        const ecs_manager = try std.heap.page_allocator.create(TestECSManager);
        ecs_manager.* = .empty;
        try ecs_manager.Init(test_ecs.Allocator());
        return .{ .mECSManager = ecs_manager };
    }

    fn Deinit(self: OtherECS, test_ecs: *TestECS) void {
        self.mECSManager.Deinit(test_ecs.mEngineContext);
        std.heap.page_allocator.destroy(self.mECSManager);
    }
};

fn MakeLabel(test_ecs: *TestECS, text: []const u8) !Label {
    var new_label: Label = .{};
    try new_label.mText.appendSlice(test_ecs.Allocator(), text);
    return new_label;
}
