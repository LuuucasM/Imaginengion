//! SDFCompiler and SDFProgram: merges in the hierarchy compiled to programs, and the programs run on the CPU. No window
//! or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const SDFProgram = @import("../../Renderer/SDFProgram.zig");
const SDFCompiler = @import("../../Renderer/SDFCompiler.zig");
const PhysicsManager = @import("../../Physics/PhysicsManager.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const MergeComponent = EntityComponents.MergeComponent;
const CombineOpComponent = EntityComponents.CombineOpComponent;
const MainObjectComponent = EntityComponents.MainObjectComponent;

const eps: f32 = 0.0001;

const RED = Vec4(f32){ .x = 1, .y = 0, .z = 0, .w = 1 };
const BLUE = Vec4(f32){ .x = 0, .y = 0, .z = 1, .w = 1 };

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mScene: Scene,
    mPrograms: SDFCompiler.Programs = .{},

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        const engine_context = try std.heap.page_allocator.create(EngineContext);
        engine_context.* = .{};
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        self.* = .{
            .mEngineContext = engine_context,
            .mScene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig),
        };
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        self.mPrograms.Deinit(engine_context.EngineAllocator());
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// A quad `size` big, at `position` in its parent's space (a new root without one), painted `color`, or with no
    /// surface for null
    fn Quad(self: *TestWorld, parent: ?Entity, position: Vec3(f32), size: Vec2(f32), color: ?Vec4(f32)) !Entity {
        const engine_context = self.mEngineContext;
        const entity = if (parent) |found|
            try found.CreateChild(engine_context, .Entity, Entity.DefaultConfig)
        else
            try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        try entity.SetTranslation(engine_context, position);
        _ = try entity.AddComponent(engine_context, ShapeComponent.MakeQuad(.{ .Size = size }));
        if (color) |paint| {
            var surface = SurfaceComponent{};
            surface.mTexOptions.mColor = paint;
            _ = try entity.AddComponent(engine_context, surface);
        }
        return entity;
    }

    /// A quad that is a part joining by `op`
    fn Part(self: *TestWorld, parent: Entity, position: Vec3(f32), size: Vec2(f32), op: CombineOpComponent) !Entity {
        const entity = try self.Quad(parent, position, size, RED);
        _ = try entity.AddComponent(self.mEngineContext, op);
        return entity;
    }

    fn Merge(self: *TestWorld, entity: Entity) !void {
        _ = try entity.AddComponent(self.mEngineContext, MergeComponent{});
    }

    fn Compile(self: *TestWorld, root: Entity) !SDFCompiler.Compiled {
        const engine_context = self.mEngineContext;
        try PhysicsManager.UpdateWorldTransforms(&engine_context.mEditorWorld, engine_context);
        return SDFCompiler.Compile(engine_context.EngineAllocator(), root, null, &self.mPrograms);
    }

    fn Eval(self: *TestWorld, compiled: SDFCompiler.Compiled, x: f32, y: f32) SDFProgram.Value {
        return SDFProgram.Eval(self.mPrograms.mInstrs.items, self.mPrograms.mParts.items, compiled.Range, .{ .x = x, .y = y, .z = 0 });
    }

    fn Codes(self: *TestWorld, compiled: SDFCompiler.Compiled) []const SDFProgram.Instr {
        return self.mPrograms.mInstrs.items[compiled.Range.First..][0..compiled.Range.Count];
    }
};

fn ExpectCodes(expected: []const SDFProgram.Code, instrs: []const SDFProgram.Instr) !void {
    try std.testing.expectEqual(expected.len, instrs.len);
    for (expected, instrs) |code, instr| try std.testing.expectEqual(code, instr.Code);
}

const SQUARE_4 = Vec2(f32){ .x = 4, .y = 4 };
const ORIGIN = Vec3(f32){ .x = 0, .y = 0, .z = 0 };

test "a merge adds first, then subtracts, then intersects, whatever order the hierarchy has them in" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    const root = try world.Quad(null, ORIGIN, SQUARE_4, RED);
    try world.Merge(root);
    _ = try world.Part(root, ORIGIN, .{ .x = 1, .y = 1 }, .{ .mOp = .Subtract });
    _ = try world.Part(root, ORIGIN, .{ .x = 1, .y = 1 }, .{ .mOp = .Intersect });
    _ = try world.Part(root, ORIGIN, .{ .x = 1, .y = 1 }, .{});

    const compiled = try world.Compile(root);
    try ExpectCodes(&.{ .Shape, .Shape, .Union, .Shape, .Subtract, .Shape, .Intersect }, world.Codes(compiled));
    try std.testing.expectEqual(@as(u32, 2), compiled.Depth);
}

test "a card with a round hole cut in it is solid around the hole, and nothing in it or past the card's edge" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    const card = try world.Quad(null, ORIGIN, SQUARE_4, RED);
    try world.Merge(card);
    const hole = try world.Part(card, ORIGIN, .{ .x = 1, .y = 1 }, .{ .mOp = .Subtract });
    hole.GetComponent(ShapeComponent).?.GetQuad().?.CornerRadii = .{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.5 };

    const compiled = try world.Compile(card);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), world.Eval(compiled, 0, 0).D, eps);
    try std.testing.expect(world.Eval(compiled, 1.5, 0).D < 0);
    try std.testing.expectApproxEqAbs(@as(f32, 1), world.Eval(compiled, 3, 0).D, eps);
}

test "a merge's parts are its whole subtree, through entities with no shape, but not a game object of its own or a hidden part" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const root = try world.Quad(null, ORIGIN, .{ .x = 1, .y = 1 }, RED);
    try world.Merge(root);
    //a part under an entity with no shape
    const pivot = try root.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try pivot.SetTranslation(engine_context, .{ .x = 10, .y = 0, .z = 0 });
    _ = try world.Quad(pivot, ORIGIN, .{ .x = 1, .y = 1 }, RED);
    //a game object of its own, not a part
    const held = try world.Quad(root, .{ .x = -10, .y = 0, .z = 0 }, .{ .x = 1, .y = 1 }, RED);
    _ = try held.AddComponent(engine_context, MainObjectComponent{});
    //hidden, so left out
    const hidden = try world.Quad(root, .{ .x = 0, .y = 10, .z = 0 }, .{ .x = 1, .y = 1 }, RED);
    hidden.GetComponent(SurfaceComponent).?.mShouldRender = false;
    //a part under a part
    const arm = try world.Quad(root, .{ .x = 0, .y = -5, .z = 0 }, .{ .x = 1, .y = 1 }, RED);
    _ = try world.Quad(arm, .{ .x = 0, .y = -5, .z = 0 }, .{ .x = 1, .y = 1 }, RED);

    const compiled = try world.Compile(root);
    try std.testing.expectEqual(@as(usize, 4), world.mPrograms.mParts.items.len);
    try std.testing.expect(world.Eval(compiled, 10, 0).D < 0);
    try std.testing.expect(world.Eval(compiled, -10, 0).D > 0);
    try std.testing.expect(world.Eval(compiled, 0, 10).D > 0);
    try std.testing.expect(world.Eval(compiled, 0, -10).D < 0);
}

test "a merge under a merge is one part, in brackets, joined by its root's op" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    //a card minus (a hole minus a peg): a peg standing in a square hole
    const card = try world.Quad(null, ORIGIN, SQUARE_4, RED);
    try world.Merge(card);
    const hole = try world.Part(card, ORIGIN, .{ .x = 2, .y = 2 }, .{ .mOp = .Subtract });
    try world.Merge(hole);
    _ = try world.Part(hole, ORIGIN, .{ .x = 1, .y = 1 }, .{ .mOp = .Subtract });

    const compiled = try world.Compile(card);
    try ExpectCodes(&.{ .Shape, .Shape, .Shape, .Subtract, .Subtract }, world.Codes(compiled));
    //the peg, the gap around it, the card around that
    try std.testing.expect(world.Eval(compiled, 0, 0).D < 0);
    try std.testing.expect(world.Eval(compiled, 0.75, 0).D > 0);
    try std.testing.expect(world.Eval(compiled, 1.5, 0).D < 0);
}

test "a long list of adds needs 2 stack slots, and merges cut into each other too deep are turned down, leaving nothing" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    const root = try world.Quad(null, ORIGIN, SQUARE_4, RED);
    try world.Merge(root);
    for (0..10) |i| _ = try world.Quad(root, .{ .x = @floatFromInt(i), .y = 0, .z = 0 }, .{ .x = 1, .y = 1 }, RED);
    try std.testing.expectEqual(@as(u32, 2), (try world.Compile(root)).Depth);

    //each a merge subtracted from the one around it: every level is one deeper than the one inside it
    const deep = try world.Quad(null, ORIGIN, SQUARE_4, RED);
    try world.Merge(deep);
    var inner = deep;
    for (0..3) |_| {
        inner = try world.Part(inner, ORIGIN, SQUARE_4, .{ .mOp = .Subtract });
        try world.Merge(inner);
    }
    try std.testing.expectEqual(@as(u32, 4), (try world.Compile(deep)).Depth);

    inner = try world.Part(inner, ORIGIN, SQUARE_4, .{ .mOp = .Subtract });
    try world.Merge(inner);
    const parts = world.mPrograms.mParts.items.len;
    const instrs = world.mPrograms.mInstrs.items.len;
    try std.testing.expectError(error.MergeTooDeep, world.Compile(deep));
    try std.testing.expectEqual(parts, world.mPrograms.mParts.items.len);
    try std.testing.expectEqual(instrs, world.mPrograms.mInstrs.items.len);
}

test "colors blend half and half where two parts tie in a smooth union, and a part with no surface takes its root's" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    //a red square left of the middle, a blue one right of it, both 1 wide, so the middle is 0.5 from each
    const root = try world.Quad(null, .{ .x = -1, .y = 0, .z = 0 }, .{ .x = 1, .y = 1 }, RED);
    try world.Merge(root);
    const blue = try world.Quad(root, .{ .x = 2, .y = 0, .z = 0 }, .{ .x = 1, .y = 1 }, BLUE);
    _ = try blue.AddComponent(world.mEngineContext, CombineOpComponent{ .mSmoothness = 0.5 });
    //no surface: red, like the root
    _ = try world.Quad(root, .{ .x = 0, .y = 5, .z = 0 }, .{ .x = 1, .y = 1 }, null);

    const compiled = try world.Compile(root);
    const middle = world.Eval(compiled, 0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), middle.D, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), middle.Color.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), middle.Color.z, eps);
    //well inside each, each its own color
    try std.testing.expectApproxEqAbs(@as(f32, 1), world.Eval(compiled, 1, 0).Color.z, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1), world.Eval(compiled, -1, 5).Color.x, eps);
}

test "a part's smoothness grows with its scale" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    const root = try world.Quad(null, ORIGIN, SQUARE_4, RED);
    try world.Merge(root);
    const part = try world.Part(root, ORIGIN, .{ .x = 1, .y = 1 }, .{ .mSmoothness = 0.25 });
    try part.SetScale(world.mEngineContext, .{ .x = 3, .y = 2, .z = 1 });

    const compiled = try world.Compile(root);
    //by its smaller axis
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), world.Codes(compiled)[2].Smoothness, eps);
}
