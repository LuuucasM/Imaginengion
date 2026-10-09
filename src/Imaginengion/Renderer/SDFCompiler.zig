//! Turns a merge (MergeComponent) in the hierarchy into an SDFProgram: which entities are its parts, in what order they
//! join, and each part placed in the world the way drawing and picking place it (ShapeGeometry.QuadBox).
//!
//! A level is one merge root and its parts. Its parts are every entity below the root with a ShapeComponent, walked
//! through entities without one, but not into a game object of its own (MainObjectComponent). A merge below it is one
//! part, compiled as a level of its own and put in like brackets. Within a level every add comes first, then every
//! subtract, then every intersect: ((A u B u C) - D - E) n F, so the hierarchy's order never changes the shape.
//! The adds go deepest first (Sethi-Ullman), since it doesn't matter which a union starts from, which keeps the stack
//! the program needs as low as it can go: a flat list of any length needs 2.
const std = @import("std");
const SDFProgram = @import("SDFProgram.zig");
const Instr = SDFProgram.Instr;
const Part = SDFProgram.Part;
const ShapeGeometry = @import("ShapeGeometry.zig");
const ShapeAxes = @import("Renderer2D.zig").ShapeAxes;
const CanvasTransform = @import("../Math/OverlayCanvas.zig").CanvasTransform;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Entity = @import("../ECSObjects/Entity.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const MergeComponent = EntityComponents.MergeComponent;
const CombineOpComponent = EntityComponents.CombineOpComponent;
const MainObjectComponent = EntityComponents.MainObjectComponent;
const Tracy = @import("../Core/Tracy.zig");

pub const Error = error{
    /// the merge needs more than SDFProgram.MAX_STACK stack slots: merges subtracted or intersected inside each other
    /// too deep
    MergeTooDeep,
} || std.mem.Allocator.Error;

/// Programs for any number of merges, one after another, all sharing one list of parts
pub const Programs = struct {
    mInstrs: std.ArrayList(Instr) = .empty,
    mParts: std.ArrayList(Part) = .empty,

    pub fn Deinit(self: *Programs, allocator: std.mem.Allocator) void {
        self.mInstrs.deinit(allocator);
        self.mParts.deinit(allocator);
    }

    pub fn Clear(self: *Programs) void {
        self.mInstrs.clearRetainingCapacity();
        self.mParts.clearRetainingCapacity();
    }
};

/// A compiled merge: where its program is, and how many stack slots it needs
pub const Compiled = struct {
    Range: SDFProgram.Range,
    Depth: u32,
};

/// The color a part with no surface of its own is given when its merge root has none either
const DEFAULT_COLOR = Vec4(f32){ .x = 1, .y = 1, .z = 1, .w = 1 };

/// Compiles the merge rooted at `root` onto the end of `programs`, which `allocator` is for. `canvas` places it for an
/// overlay scene, as it does for drawing
pub fn Compile(allocator: std.mem.Allocator, root: Entity, canvas: ?CanvasTransform, programs: *Programs) Error!Compiled {
    const zone = Tracy.ZoneInit("SDFCompiler::Compile", @src());
    defer zone.Deinit();

    //what is only needed while compiling: each level's operands and code
    var temp = std.heap.ArenaAllocator.init(allocator);
    defer temp.deinit();
    var compiler = Compiler{ .mAllocator = allocator, .mTemp = temp.allocator(), .mCanvas = canvas, .mPrograms = programs };
    //a merge turned down leaves nothing behind
    const parts_before = programs.mParts.items.len;
    errdefer programs.mParts.shrinkRetainingCapacity(parts_before);
    const level = try compiler.CompileLevel(root, DEFAULT_COLOR);
    const first: u32 = @intCast(programs.mInstrs.items.len);
    try programs.mInstrs.appendSlice(allocator, level.Code.items);
    return .{ .Range = .{ .First = first, .Count = @intCast(level.Code.items.len) }, .Depth = level.Depth };
}

/// One thing a level joins: a part, or a merge below it in brackets, as the code that pushes it
const Operand = struct {
    Code: std.ArrayList(Instr),
    Depth: u32,
    Op: CombineOpComponent.Op,
    Smoothness: f32,

    fn DeeperFirst(_: void, a: Operand, b: Operand) bool {
        return a.Depth > b.Depth;
    }
};

const Compiler = struct {
    //for the programs
    mAllocator: std.mem.Allocator,
    //for everything else
    mTemp: std.mem.Allocator,
    mCanvas: ?CanvasTransform,
    mPrograms: *Programs,

    /// The code for one level, rooted at `root`. `inherited` is the color its parts take when neither they nor the root
    /// have a surface. A merge below it is compiled by calling this again, so it goes as deep as merges are put in
    /// merges, which MAX_STACK keeps short for any that isn't the first thing added
    fn CompileLevel(self: *Compiler, root: Entity, inherited: Vec4(f32)) Error!Operand {
        const color = if (root.GetComponent(SurfaceComponent)) |surface| surface.mTexOptions.mColor else inherited;

        var adds: std.ArrayList(Operand) = .empty;
        var subtracts: std.ArrayList(Operand) = .empty;
        var intersects: std.ArrayList(Operand) = .empty;

        //the root's own shape is the first thing added. its op says how this level joins the one around it, if any
        if (try self.PartOperand(root, color)) |own| try adds.append(self.mTemp, .{ .Code = own.Code, .Depth = own.Depth, .Op = .Union, .Smoothness = 0 });

        //the rest of the subtree, in order: a work list rather than recursion, children pushed last first
        var to_visit: std.ArrayList(Entity) = .empty;
        try self.PushChildren(&to_visit, root);
        while (to_visit.pop()) |entity| {
            if (entity.HasComponent(MainObjectComponent)) continue;

            const operand: ?Operand = if (entity.HasComponent(MergeComponent)) blk: {
                var bracket = try self.CompileLevel(entity, color);
                const op = OpOf(entity);
                bracket.Op = op.mOp;
                bracket.Smoothness = self.WorldSmoothness(entity, op.mSmoothness);
                break :blk bracket;
            } else try self.PartOperand(entity, color);

            if (operand) |found| {
                switch (found.Op) {
                    .Union => try adds.append(self.mTemp, found),
                    .Subtract => try subtracts.append(self.mTemp, found),
                    .Intersect => try intersects.append(self.mTemp, found),
                }
            }
            //a merge below is its own level, everything else is walked through
            if (!entity.HasComponent(MergeComponent)) try self.PushChildren(&to_visit, entity);
        }

        //nothing added: nothing to cut or trim either
        var level = Operand{ .Code = .empty, .Depth = 1, .Op = .Union, .Smoothness = 0 };
        if (adds.items.len == 0) {
            try level.Code.append(self.mTemp, .{ .Code = .Empty });
            return level;
        }

        //stable, so equally deep adds keep the hierarchy's order
        std.sort.insertion(Operand, adds.items, {}, Operand.DeeperFirst);
        try level.Code.appendSlice(self.mTemp, adds.items[0].Code.items);
        level.Depth = adds.items[0].Depth;
        for (adds.items[1..]) |operand| try self.Join(&level, operand, .Union);
        for (subtracts.items) |operand| try self.Join(&level, operand, .Subtract);
        for (intersects.items) |operand| try self.Join(&level, operand, .Intersect);

        if (level.Depth > SDFProgram.MAX_STACK) return error.MergeTooDeep;
        return level;
    }

    /// Puts `operand` after what `level` has so far and joins the two with `code`. What is so far takes a slot while
    /// the operand is worked out
    fn Join(self: *Compiler, level: *Operand, operand: Operand, code: SDFProgram.Code) Error!void {
        try level.Code.appendSlice(self.mTemp, operand.Code.items);
        try level.Code.append(self.mTemp, .{ .Code = code, .Smoothness = operand.Smoothness });
        level.Depth = @max(level.Depth, operand.Depth + 1);
    }

    /// `entity` as a part: a Shape instruction for it, with its part added to the programs. Null if it has no shape or
    /// transform, or its surface is hidden. A part with no surface (a cutter, usually) takes `color`
    fn PartOperand(self: *Compiler, entity: Entity, color: Vec4(f32)) Error!?Operand {
        const shape = entity.GetComponent(ShapeComponent) orelse return null;
        const transform = entity.GetComponent(TransformComponent) orelse return null;
        const surface = entity.GetComponent(SurfaceComponent);
        if (surface) |found| {
            if (!found.mShouldRender) return null;
        }

        const part_ind: u32 = @intCast(self.mPrograms.mParts.items.len);
        switch (shape.mKind) {
            .Quad => |quad| {
                const box = ShapeGeometry.QuadBox(transform, quad, 0, self.mCanvas);
                const axes = ShapeAxes(box.Center, box.Rotation);
                try self.mPrograms.mParts.append(self.mAllocator, .{
                    .AxisX = axes[0],
                    .AxisY = axes[1],
                    .AxisZ = axes[2],
                    .Size = .{ box.HalfExtents.x, box.HalfExtents.y },
                    .Kind = .Quad,
                    .Params = box.CornerRadii.ToArray(),
                    .Color = (if (surface) |found| found.mTexOptions.mColor else color).ToArray(),
                });
            },
        }

        const op = OpOf(entity);
        var code: std.ArrayList(Instr) = .empty;
        try code.append(self.mTemp, .{ .Code = .Shape, .Part = part_ind });
        return .{ .Code = code, .Depth = 1, .Op = op.mOp, .Smoothness = self.WorldSmoothness(entity, op.mSmoothness) };
    }

    /// A smoothness in world units: grown by the entity's scale the way a quad's corner radii are, by its smaller axis
    /// (and the canvas for an overlay one), so a merge looks the same at any size
    fn WorldSmoothness(self: *Compiler, entity: Entity, smoothness: f32) f32 {
        const transform = entity.GetComponent(TransformComponent) orelse return smoothness;
        const world_scale = transform.GetWorldScale();
        const canvas_scale: f32 = if (self.mCanvas) |c| c.Scale else 1.0;
        return smoothness * @min(world_scale.x, world_scale.y) * canvas_scale;
    }

    fn PushChildren(self: *Compiler, to_visit: *std.ArrayList(Entity), entity: Entity) Error!void {
        const start = to_visit.items.len;
        var children = entity.GetIterator(.Child);
        while (children.next()) |child| try to_visit.append(self.mTemp, child);
        std.mem.reverse(Entity, to_visit.items[start..]);
    }
};

/// An entity's op, a plain Union without a CombineOpComponent
fn OpOf(entity: Entity) CombineOpComponent {
    return if (entity.GetComponent(CombineOpComponent)) |op| op.* else .{};
}
