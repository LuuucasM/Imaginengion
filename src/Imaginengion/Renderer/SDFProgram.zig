//! A compound SDF (MergeComponent) as a program: the shape's tree of ops written out in postfix, the way a stack
//! machine runs it. A Shape instruction pushes one part's distance and color, and an op pops two and pushes what they
//! combine to, so a program of any nesting runs top to bottom with a few stack slots and no tree. SDFCompiler writes
//! programs from the hierarchy; Eval runs one. Eval is written the way SDFRayMarcher is, no allocator and fixed arrays,
//! so the shaders can run the same code over their buffers.
//!
//! Every part is a quad so far, so every program is 2D: it is run at points in its merge root's plane, and each quad
//! is measured in its own plane (its rounded rectangle's 2D distance). A part turned out of the root's plane is cut
//! through where it crosses it. The renderer gives the result its plate's thickness once, at the end, the same way a
//! quad is its 2D rectangle extruded.
const std = @import("std");
const builtin = @import("builtin");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const SDFFunctions = @import("../Math/SDFFunctions.zig");
const GPUAsserts = @import("../Core/GPUAsserts.zig");

const is_spirv = builtin.target.cpu.arch.isSpirV();

/// How many values a program can have on its stack at once. SDFCompiler orders a merge's parts to keep this low (a flat
/// list of any length needs 2) and turns down a merge that would need more
pub const MAX_STACK: u32 = 4;

/// The distance Empty pushes: further than anything, so a union with it is the other side, and a subtract or intersect
/// on it stays nothing. Finite, so two of them can still be told apart from each other without making a NaN
pub const EMPTY_DISTANCE: f32 = 1e30;

pub const Code = enum(u32) {
    /// pushes part Part's distance and color
    Shape,
    /// pushes nothing at all: a merge with nothing to add
    Empty,
    /// pops b then a, pushes a and b joined (SDFFunctions.opSmoothUnion), colors mixed where they blend
    Union,
    /// pops b then a, pushes a with b cut out, colored as a was
    Subtract,
    /// pops b then a, pushes what is inside both, colored as a was
    Intersect,
};

pub const Instr = extern struct {
    Code: Code,
    //Shape: which part, an index into the parts
    Part: u32 = 0,
    //the ops: how smoothly the two join, in world units. 0 is sharp
    Smoothness: f32 = 0,
    _Pad: u32 = 0,
};

pub const PartKind = enum(u32) {
    Quad,
};

/// One part of a merge, placed in the world. The same axes as a ShapeData: its own x, y and z axes in world space, each
/// with -dot(axis, center) in w
pub const Part = extern struct {
    AxisX: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    AxisY: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    AxisZ: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    //a quad's half width and height, in world units
    Size: if (is_spirv) Vec2(f32).VectorT else Vec2(f32).ArrayT,
    Kind: PartKind,
    _Pad: u32 = 0,
    //a quad's corner radii, in world units, in SDFFunctions' order
    Params: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT align(16),
    //its surface's color
    Color: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
};

comptime {
    GPUAsserts.AssertGPULayout(Instr);
    GPUAsserts.AssertGPULayout(Part);
}

/// Where one merge's program is in a list of instructions shared by many
pub const Range = struct {
    First: u32,
    Count: u32,
};

/// What a program comes to at a point: the distance to the merged shape, in the root's plane, and its color there
pub const Value = struct {
    D: f32,
    Color: Vec4(f32),
};

/// Runs the program in `range` of `instrs` at `point`, a world point in the merge root's plane. `instrs` and `parts`
/// are anything indexed like an array of Instr and of Part: slices on the CPU, storage buffers on the GPU
pub fn Eval(instrs: anytype, parts: anytype, range: Range, point: Vec3(f32)) Value {
    var stack: [MAX_STACK]Value = undefined;
    var top: u32 = 0;
    for (range.First..range.First + range.Count) |i| {
        const instr: Instr = instrs[i];
        switch (instr.Code) {
            .Shape => {
                const part: Part = parts[instr.Part];
                stack[top] = .{ .D = PartDistance(part, point), .Color = .FromVector(part.Color) };
                top += 1;
            },
            .Empty => {
                stack[top] = .{ .D = EMPTY_DISTANCE, .Color = .{ .x = 0, .y = 0, .z = 0, .w = 0 } };
                top += 1;
            },
            .Union, .Subtract, .Intersect => {
                top -= 1;
                stack[top - 1] = Combine(instr, stack[top - 1], stack[top]);
            },
        }
    }
    return stack[0];
}

fn Combine(instr: Instr, a: Value, b: Value) Value {
    return switch (instr.Code) {
        .Union => blk: {
            const blend = SDFFunctions.opSmoothUnion(a.D, b.D, instr.Smoothness);
            break :blk .{ .D = blend.D, .Color = a.Color.Lerp(b.Color, blend.W) };
        },
        //a cut or a trim takes nothing away from the color of what is left
        .Subtract => .{ .D = SDFFunctions.opSmoothSubtraction(a.D, b.D, instr.Smoothness).D, .Color = a.Color },
        .Intersect => .{ .D = SDFFunctions.opSmoothIntersection(a.D, b.D, instr.Smoothness).D, .Color = a.Color },
        .Shape, .Empty => a,
    };
}

//==================================masks==================================

/// A shape's mask index when no mask is over it
pub const NO_MASK: u32 = std.math.maxInt(u32);

pub const MaskOp = enum(u32) {
    /// keeps only what is inside the mask's shape
    Intersect,
    /// cuts the mask's shape out
    Subtract,
};

/// A mask (MaskComponent) as the GPU reads it: its shape's program, what it does with it, and the mask it is inside
/// itself. A mask is always added after the one it is inside, so following Parent always ends
pub const MaskData = extern struct {
    First: u32,
    Count: u32,
    Op: MaskOp,
    //the mask around this one, NO_MASK for none
    Parent: u32,
};

comptime {
    GPUAsserts.AssertGPULayout(MaskData);
}

/// Whether `point` is kept by mask `mask_ind` and every mask around it. Each mask's program is run at the point, and
/// it is measured in the mask's own plane, so the cut goes straight through depth
pub fn InMasks(masks: anytype, instrs: anytype, parts: anytype, mask_ind: u32, point: Vec3(f32)) bool {
    var ind = mask_ind;
    while (ind != NO_MASK) {
        const mask: MaskData = masks[ind];
        const distance = Eval(instrs, parts, .{ .First = mask.First, .Count = mask.Count }, point).D;
        const kept = switch (mask.Op) {
            .Intersect => distance <= 0,
            .Subtract => distance > 0,
        };
        if (!kept) return false;
        ind = mask.Parent;
    }
    return true;
}

/// A shape's `distance` cut by mask `mask_ind` and every mask around it, so a march doesn't step toward a part of the
/// shape that is never drawn
pub fn Masked(masks: anytype, instrs: anytype, parts: anytype, mask_ind: u32, distance: f32, point: Vec3(f32)) f32 {
    var masked = distance;
    var ind = mask_ind;
    while (ind != NO_MASK) {
        const mask: MaskData = masks[ind];
        const mask_distance = Eval(instrs, parts, .{ .First = mask.First, .Count = mask.Count }, point).D;
        masked = switch (mask.Op) {
            .Intersect => SDFFunctions.opIntersection(masked, mask_distance),
            .Subtract => SDFFunctions.opSubtraction(masked, mask_distance),
        };
        ind = mask.Parent;
    }
    return masked;
}

/// A part's 2D distance at a point, measured in the part's own plane
fn PartDistance(part: Part, point: Vec3(f32)) f32 {
    const axis_x: Vec4(f32) = .FromVector(part.AxisX);
    const axis_y: Vec4(f32) = .FromVector(part.AxisY);
    const local = Vec2(f32){
        .x = axis_x.ToVec3().Dot(point) + axis_x.w,
        .y = axis_y.ToVec3().Dot(point) + axis_y.w,
    };
    return switch (part.Kind) {
        .Quad => SDFFunctions.sdRoundedBox2D(local, .FromVector(part.Size), .FromVector(part.Params)),
    };
}
