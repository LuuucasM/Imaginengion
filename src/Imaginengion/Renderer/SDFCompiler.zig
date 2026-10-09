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
const Vec3 = MathTypes.Vec3;
const Vec2 = MathTypes.Vec2;
const Quat = MathTypes.Quat;
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
    /// Which entity's surface paints each part, by the part's index, null for none (plain white): its own surface, or
    /// else its merge root's, or else the merge around that's. CPU only: whoever draws a merge turns these into its
    /// parts' Shading
    mPartSurfaces: std.ArrayList(?Entity) = .empty,

    pub fn Deinit(self: *Programs, allocator: std.mem.Allocator) void {
        self.mInstrs.deinit(allocator);
        self.mParts.deinit(allocator);
        self.mPartSurfaces.deinit(allocator);
    }

    pub fn Clear(self: *Programs) void {
        self.mInstrs.clearRetainingCapacity();
        self.mParts.clearRetainingCapacity();
        self.mPartSurfaces.clearRetainingCapacity();
    }
};

/// A compiled merge: where its program is, how many stack slots it needs, where its parts are, and the rectangle in its
/// root's plane it can reach
pub const Compiled = struct {
    Range: SDFProgram.Range,
    Depth: u32,
    /// its parts, in the programs' parts
    Parts: SDFProgram.Range,
    /// the merge root's plane in the world: its place and turn, placed by the canvas for an overlay one
    Center: Vec3(f32),
    Rotation: Quat(f32),
    /// the rectangle in that plane, in the root's own x and y, that every part lies within, grown by the smoothest join
    /// since a smooth union can push the surface out by up to its smoothness. Min past Max when there are no parts
    Min: Vec2(f32),
    Max: Vec2(f32),
};


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
    errdefer {
        programs.mParts.shrinkRetainingCapacity(parts_before);
        programs.mPartSurfaces.shrinkRetainingCapacity(parts_before);
    }
    const level = try compiler.CompileLevel(root, null);
    const first: u32 = @intCast(programs.mInstrs.items.len);
    try programs.mInstrs.appendSlice(allocator, level.Code.items);
    return compiler.Finish(root, .{ .First = first, .Count = @intCast(level.Code.items.len) }, level.Depth, @intCast(parts_before));
}

/// Compiles just `entity`'s own shape onto the end of `programs`, a program of one part: what a mask (MaskComponent)
/// cuts with. Its surface doesn't matter, a hidden or missing one still cuts. Null for an entity with no shape or
/// transform
pub fn CompileShape(allocator: std.mem.Allocator, entity: Entity, canvas: ?CanvasTransform, programs: *Programs) Error!?Compiled {
    var compiler = Compiler{ .mAllocator = allocator, .mTemp = allocator, .mCanvas = canvas, .mPrograms = programs };
    const part_ind = try compiler.AddPart(entity, null) orelse return null;
    const first: u32 = @intCast(programs.mInstrs.items.len);
    try programs.mInstrs.append(allocator, .{ .Code = .Shape, .Part = part_ind });
    return compiler.Finish(entity, .{ .First = first, .Count = 1 }, 1, part_ind);
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
    //the smoothest join so far, in world units: how far past its parts the merge can reach
    mMaxSmoothness: f32 = 0,

    /// The compiled program's place, and the plane and rectangle its parts (from `first_part` on) lie within
    fn Finish(self: *Compiler, root: Entity, range: SDFProgram.Range, depth: u32, first_part: u32) Compiled {
        const transform = root.GetComponent(TransformComponent);
        var center = if (transform) |found| found.GetWorldPosition() else Vec3(f32){ .x = 0, .y = 0, .z = 0 };
        var rotation = if (transform) |found| found.GetWorldRotation() else Quat(f32){ .w = 1, .x = 0, .y = 0, .z = 0 };
        if (self.mCanvas) |c| {
            center = c.ToWorldPoint(center);
            rotation = c.ToWorldRotation(rotation);
        }

        //each part's corners in the root's plane: its own x and y axes are the rows of its axes, unit length
        const plane = ShapeAxes(center, rotation);
        const big = std.math.floatMax(f32);
        var min = Vec2(f32){ .x = big, .y = big };
        var max = Vec2(f32){ .x = -big, .y = -big };
        const parts = self.mPrograms.mParts.items[first_part..];
        for (parts) |part| {
            const axis_x: Vec4(f32) = .FromArray(part.AxisX);
            const axis_y: Vec4(f32) = .FromArray(part.AxisY);
            const axis_z: Vec4(f32) = .FromArray(part.AxisZ);
            const part_center = axis_x.ToVec3().MulScalar(-axis_x.w).AddVec(axis_y.ToVec3().MulScalar(-axis_y.w)).AddVec(axis_z.ToVec3().MulScalar(-axis_z.w));
            const reach_x = axis_x.ToVec3().MulScalar(part.Size[0]);
            const reach_y = axis_y.ToVec3().MulScalar(part.Size[1]);
            for ([_]f32{ -1, 1 }) |sx| {
                for ([_]f32{ -1, 1 }) |sy| {
                    const corner = part_center.AddVec(reach_x.MulScalar(sx)).AddVec(reach_y.MulScalar(sy));
                    const local = Vec2(f32){
                        .x = Vec4(f32).FromArray(plane[0]).ToVec3().Dot(corner) + plane[0][3],
                        .y = Vec4(f32).FromArray(plane[1]).ToVec3().Dot(corner) + plane[1][3],
                    };
                    min = .{ .x = @min(min.x, local.x), .y = @min(min.y, local.y) };
                    max = .{ .x = @max(max.x, local.x), .y = @max(max.y, local.y) };
                }
            }
        }
        if (parts.len > 0) {
            min = min.SubVec(.{ .x = self.mMaxSmoothness, .y = self.mMaxSmoothness });
            max = max.AddVec(.{ .x = self.mMaxSmoothness, .y = self.mMaxSmoothness });
        }

        return .{
            .Range = range,
            .Depth = depth,
            .Parts = .{ .First = first_part, .Count = @intCast(parts.len) },
            .Center = center,
            .Rotation = rotation,
            .Min = min,
            .Max = max,
        };
    }

    /// The code for one level, rooted at `root`. `inherited` is the entity whose surface paints its parts when neither
    /// have a surface. A merge below it is compiled by calling this again, so it goes as deep as merges are put in
    /// merges, which MAX_STACK keeps short for any that isn't the first thing added
    fn CompileLevel(self: *Compiler, root: Entity, inherited: ?Entity) Error!Operand {
        const painter = if (root.HasComponent(SurfaceComponent)) root else inherited;

        var adds: std.ArrayList(Operand) = .empty;
        var subtracts: std.ArrayList(Operand) = .empty;
        var intersects: std.ArrayList(Operand) = .empty;

        //the root's own shape is the first thing added. its op says how this level joins the one around it, if any
        if (try self.PartOperand(root, painter)) |own| try adds.append(self.mTemp, .{ .Code = own.Code, .Depth = own.Depth, .Op = .Union, .Smoothness = 0 });

        //the rest of the subtree, in order: a work list rather than recursion, children pushed last first
        var to_visit: std.ArrayList(Entity) = .empty;
        try self.PushChildren(&to_visit, root);
        while (to_visit.pop()) |entity| {
            if (entity.HasComponent(MainObjectComponent)) continue;

            const operand: ?Operand = if (entity.HasComponent(MergeComponent)) blk: {
                var bracket = try self.CompileLevel(entity, painter);
                const op = OpOf(entity);
                bracket.Op = op.mOp;
                bracket.Smoothness = self.WorldSmoothness(entity, op.mSmoothness);
                break :blk bracket;
            } else try self.PartOperand(entity, painter);

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
        self.mMaxSmoothness = @max(self.mMaxSmoothness, operand.Smoothness);
    }

    /// `entity` as a part: a Shape instruction for it, with its part added to the programs. Null if it has no shape or
    /// transform, or its surface is hidden. A part with no surface (a cutter, usually) is painted by `painter`'s
    fn PartOperand(self: *Compiler, entity: Entity, painter: ?Entity) Error!?Operand {
        if (entity.GetComponent(SurfaceComponent)) |surface| {
            if (!surface.mShouldRender) return null;
        }
        const part_ind = try self.AddPart(entity, painter) orelse return null;

        const op = OpOf(entity);
        var code: std.ArrayList(Instr) = .empty;
        try code.append(self.mTemp, .{ .Code = .Shape, .Part = part_ind });
        return .{ .Code = code, .Depth = 1, .Op = op.mOp, .Smoothness = self.WorldSmoothness(entity, op.mSmoothness) };
    }

    /// Adds `entity`'s shape to the programs' parts, placed the way drawing and picking place it, and painted by its
    /// own surface or else `painter`'s. Returns its index, or null if it has no shape or transform
    fn AddPart(self: *Compiler, entity: Entity, painter: ?Entity) Error!?u32 {
        const shape = entity.GetComponent(ShapeComponent) orelse return null;
        const transform = entity.GetComponent(TransformComponent) orelse return null;
        try self.mPrograms.mPartSurfaces.append(self.mAllocator, if (entity.HasComponent(SurfaceComponent)) entity else painter);

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
                });
            },
        }
        return part_ind;
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
