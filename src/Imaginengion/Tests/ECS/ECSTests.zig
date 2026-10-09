//! Integration tests for the ECS: entity lifetime, hierarchy, queries, deferred events and duplication.
//! These drive a real ECSManager built from the test components below, so they do not depend on the
//! engine's component lists. Run with `zig build test`.
const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const ECS = @import("../../ECS/ECSManager.zig");

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

    /// end of frame: applies everything queued by DestroyEntity and RemoveComponent
    fn ProcessEvents(self: *TestECS) !void {
        var callback_list: std.DoublyLinkedList = .{};
        try self.mECSManager.ProcessEvents(self.mEngineContext, .EndOfFrame, &callback_list);
    }
};

test "RemoveComponentSync takes the component off before it returns" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const entity_id = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponent(allocator, entity_id, Health{});
    _ = try test_ecs.mECSManager.AddComponent(allocator, entity_id, Position{ .x = 3 });

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
    _ = try test_ecs.mECSManager.AddComponent(allocator, entity_id, Health{});
    try std.testing.expect(test_ecs.mECSManager.HasComponent(Health, entity_id));
    try test_ecs.mECSManager.RemoveComponentSync(test_ecs.mEngineContext, entity_id, Health.Ind);
    try std.testing.expect(!test_ecs.mECSManager.HasComponent(Health, entity_id));
}

test "a sync removal and a queued removal of the same component do not collide" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const entity_id = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponent(allocator, entity_id, Health{});

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

    _ = try test_ecs.mECSManager.AddComponent(allocator, entity_1, Position{ .x = 5 });
    _ = try test_ecs.mECSManager.AddComponent(allocator, entity_1, try MakeLabel(test_ecs, "player"));
    _ = try test_ecs.mECSManager.AddComponent(allocator, entity_2, Position{ .x = 9 });

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

    _ = try ecs.AddComponent(allocator, p, Position{});
    _ = try ecs.AddComponent(allocator, h, Health{});
    _ = try ecs.AddComponent(allocator, ph, Position{});
    _ = try ecs.AddComponent(allocator, ph, Health{});
    _ = try ecs.AddComponent(allocator, phl, Position{});
    _ = try ecs.AddComponent(allocator, phl, Health{});
    _ = try ecs.AddComponent(allocator, phl, try MakeLabel(test_ecs, "all"));

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

test "ECS destroy is deferred until ProcessEvents" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const entity_id = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponent(allocator, entity_id, try MakeLabel(test_ecs, "doomed"));

    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, entity_id);
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(entity_id)); //still readable this frame

    try test_ecs.ProcessEvents();
    try std.testing.expect(!test_ecs.mECSManager.IsActiveEntity(entity_id));
}

test "ECS destroy takes the whole subtree" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const root = try test_ecs.mECSManager.CreateEntity(allocator);
    const child_1 = try test_ecs.mECSManager.AddChild(allocator, root, .Entity);
    const child_2 = try test_ecs.mECSManager.AddChild(allocator, root, .Entity);
    const script = try test_ecs.mECSManager.AddChild(allocator, root, .Script);
    const grandchild = try test_ecs.mECSManager.AddChild(allocator, child_1, .Entity);

    _ = try test_ecs.mECSManager.AddComponent(allocator, grandchild, try MakeLabel(test_ecs, "deep"));

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
    const child_1 = try test_ecs.mECSManager.AddChild(allocator, root, .Entity);
    const child_2 = try test_ecs.mECSManager.AddChild(allocator, root, .Entity);
    const child_3 = try test_ecs.mECSManager.AddChild(allocator, root, .Entity);

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
    const child = try test_ecs.mECSManager.AddChild(allocator, root, .Entity);
    const script = try test_ecs.mECSManager.AddChild(allocator, root, .Script);

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

test "ECS remove component is deferred and survives duplicate events" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const entity_id = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponent(allocator, entity_id, try MakeLabel(test_ecs, "temp"));
    _ = try test_ecs.mECSManager.AddComponent(allocator, entity_id, Health{});

    try test_ecs.mECSManager.RemoveComponent(test_ecs.mEngineContext, entity_id, Label.Ind);
    try test_ecs.mECSManager.RemoveComponent(test_ecs.mEngineContext, entity_id, Label.Ind); //queued twice on purpose
    try std.testing.expect(test_ecs.mECSManager.HasComponent(Label, entity_id));

    try test_ecs.ProcessEvents();
    try std.testing.expect(!test_ecs.mECSManager.HasComponent(Label, entity_id));
    try std.testing.expect(test_ecs.mECSManager.HasComponent(Health, entity_id));

    //a removal queued for an entity that is destroyed in the same batch
    try test_ecs.mECSManager.RemoveComponent(test_ecs.mEngineContext, entity_id, Health.Ind);
    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, entity_id);
    try test_ecs.ProcessEvents();
    try std.testing.expect(!test_ecs.mECSManager.IsActiveEntity(entity_id));
}

test "ECS duplicate copies components, clones owned memory and copies the subtree" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const allocator = test_ecs.Allocator();

    const root = try test_ecs.mECSManager.CreateEntity(allocator);
    _ = try test_ecs.mECSManager.AddComponent(allocator, root, Position{ .x = 3 });
    _ = try test_ecs.mECSManager.AddComponent(allocator, root, try MakeLabel(test_ecs, "original"));

    const child = try test_ecs.mECSManager.AddChild(allocator, root, .Entity);
    _ = try test_ecs.mECSManager.AddComponent(allocator, child, try MakeLabel(test_ecs, "child"));
    const script = try test_ecs.mECSManager.AddChild(allocator, root, .Script);
    _ = try test_ecs.mECSManager.AddComponent(allocator, script, Health{ .mHP = 7 });

    const copy = try test_ecs.mECSManager.DuplicateEntity(test_ecs.mEngineContext, root);

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
    const child = try test_ecs.mECSManager.AddChild(allocator, root, .Entity);
    _ = try test_ecs.mECSManager.AddComponent(allocator, child, Position{ .x = 1 });

    const copy = try test_ecs.mECSManager.DuplicateEntity(test_ecs.mEngineContext, child);

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
    _ = try test_ecs.mECSManager.AddComponent(allocator, entity_id, try MakeLabel(test_ecs, "gone"));
    _ = try test_ecs.mECSManager.AddChild(allocator, entity_id, .Entity);
    try test_ecs.mECSManager.DestroyEntity(test_ecs.mEngineContext, entity_id); //leave an event queued too

    test_ecs.mECSManager.clearAndFree(test_ecs.mEngineContext);

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
    _ = try test_ecs.mECSManager.AddComponent(allocator, root, Position{ .x = 4 });
    _ = try test_ecs.mECSManager.AddComponent(allocator, root, try MakeLabel(test_ecs, "root"));

    const child = try test_ecs.mECSManager.AddChild(allocator, root, .Entity);
    _ = try test_ecs.mECSManager.AddComponent(allocator, child, try MakeLabel(test_ecs, "child"));
    const script = try test_ecs.mECSManager.AddChild(allocator, root, .Script);
    _ = try test_ecs.mECSManager.AddComponent(allocator, script, Health{ .mHP = 7 });

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
    _ = try test_ecs.mECSManager.AddComponent(allocator, entity_id, try MakeLabel(test_ecs, "doomed"));
    try test_ecs.mECSManager.DestroyEntity(engine_context, entity_id); //left queued on purpose

    const other = try OtherECS.Init(test_ecs);
    defer other.Deinit(test_ecs);

    try test_ecs.mECSManager.Copy(engine_context, other.mECSManager);

    //the destroy came across still queued, and applies to the copy's own entity
    try std.testing.expect(other.mECSManager.IsActiveEntity(entity_id));
    var callback_list: std.DoublyLinkedList = .{};
    try other.mECSManager.ProcessEvents(engine_context, .EndOfFrame, &callback_list);
    try std.testing.expect(!other.mECSManager.IsActiveEntity(entity_id));
    try std.testing.expect(test_ecs.mECSManager.IsActiveEntity(entity_id));
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
