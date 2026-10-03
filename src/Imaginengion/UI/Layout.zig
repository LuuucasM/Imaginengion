//! Layout works out the size and position of every element in a UI tree from what each one asks for: a
//! container stacks its children in a row or a column or wraps them into a grid, and an element can be a fixed
//! size, fit what it holds,
//! fill leftover space, take a share of its parent, or pin itself to a point of its parent. Pure: nodes in,
//! results out, no ECS, so the rules can be tested on their own. The layout system builds the nodes from
//! LayoutComponent / LayoutItemComponent and writes the results back as translations and shape sizes.
//!
//! Units are whatever the tree is authored in (canvas units for an overlay), y up. An element's position is
//! its center, relative to its parent's center, which is exactly its local translation.
//!
//! Each axis is solved in two passes: bottom up, every element works out the size it would like (fixed, or
//! what it holds); top down, every container hands out its own final size to its children, giving leftover
//! space to the ones that fill. Children that don't fit overflow, they are never squeezed.
//!
//! This covers what the editor's panels need (the audit of its ImGui use). New kinds of sizing, placement or
//! container are new cases in the unions and enums below, each handled in the pass it affects.
const std = @import("std");
const Vec2 = @import("../Math/MathTypes.zig").Vec2;

pub const Index = u32;

/// How big an element is along one axis
pub const Sizing = union(enum) {
    /// exactly this big
    Fixed: f32,
    /// big enough for what it holds: its content for a leaf, its children plus padding and gaps for a container
    Fit,
    /// its fit size plus a share of the space its parent has left along the parent's direction, by this weight
    /// (equal weights split it equally). Across its parent's direction it fills the parent
    Fill: f32,
    /// this fraction (0 to 1) of the parent's inner size, or of the root area for a root. Counts as nothing
    /// towards a parent that fits its children, which would otherwise depend on itself
    Percent: f32,
};

pub const Axis = enum { X, Y };

/// How a container arranges its children: a row runs left to right, a column top to bottom. A grid runs left to
/// right and wraps onto the next row down after its Columns, every cell the size of its biggest child
pub const Direction = enum {
    Row,
    Column,
    Grid,

    fn MainAxis(self: Direction) Axis {
        return switch (self) {
            .Row, .Grid => .X,
            .Column => .Y,
        };
    }
};

/// Which ways a container scrolls: its children are moved by its scroll offset, which is kept between 0 and how far
/// they run past it. A container that scrolls one way never centers what overflows it that way: it starts at the
/// start edge, so all of it can be scrolled to
pub const Scroll = enum {
    None,
    Vertical,
    Horizontal,
    Both,

    pub fn Along(self: Scroll, axis: Axis) bool {
        return switch (axis) {
            .X => self == .Horizontal or self == .Both,
            .Y => self == .Vertical or self == .Both,
        };
    }
};

/// How many columns a grid has before it wraps
pub const Columns = union(enum) {
    /// as many cells as fit across the grid's width, which it takes from its parent (Fill, Percent or Fixed). A grid
    /// that fits its children has no width to fit them in, so it is one row
    Auto,
    /// this many, e.g. a 3 x 3 inventory
    Count: u32,
};

/// Where a container's children sit along its direction when they don't fill it: from its start (the left of
/// a row, the top of a column), or centered
pub const MainAlign = enum { Start, Center };

/// Where each child sits across a container's direction: at the start (the top of a row, the left of a
/// column), or centered
pub const CrossAlign = enum { Start, Center };

pub const Padding = struct {
    Left: f32 = 0,
    Right: f32 = 0,
    Top: f32 = 0,
    Bottom: f32 = 0,

    pub fn All(amount: f32) Padding {
        return .{ .Left = amount, .Right = amount, .Top = amount, .Bottom = amount };
    }

    fn Along(self: Padding, axis: Axis) f32 {
        return switch (axis) {
            .X => self.Left + self.Right,
            .Y => self.Top + self.Bottom,
        };
    }
};

/// What makes an element a container: how it arranges its children
pub const Container = struct {
    Direction: Direction = .Column,
    Padding: Padding = .{},
    /// between each pair of children along the direction. In a grid, between its columns and between its rows
    Gap: f32 = 0,
    /// not used by a grid: its cells start at the top left, and each child sits at its cell's top left
    MainAlign: MainAlign = .Start,
    CrossAlign: CrossAlign = .Start,
    /// only used by a grid
    Columns: Columns = .Auto,
    Scroll: Scroll = .None,
    /// how far the children are scrolled: x to the right, y down. Kept within range, see Result.ScrollOffset
    ScrollOffset: Vec2(f32) = .{ .x = 0, .y = 0 },
};

/// A point of a rectangle, from -1 to 1 across each axis around its center: (0, 0) is the middle, (1, 1) the
/// top right corner and (-1, -1) the bottom left
pub const Anchoring = struct {
    /// the point of the parent's whole rectangle (padding included) the element is pinned to
    Anchor: Vec2(f32) = .{ .x = 0, .y = 0 },
    /// the point of the element that goes on the anchor
    Pivot: Vec2(f32) = .{ .x = 0, .y = 0 },
    /// moved this much from there
    Offset: Vec2(f32) = .{ .x = 0, .y = 0 },
};

pub const Placement = union(enum) {
    /// stacked by the parent with its other flow children
    Flow,
    /// pinned to a point of the parent instead, taking no room in the stack, e.g. a close button in a corner.
    /// For a root, pinned to the root area
    Anchored: Anchoring,
};

/// What a leaf holds, which is what it fits to. A container fits to its children instead
pub const Content = union(enum) {
    None,
    /// the size of what it holds, e.g. a line of text
    Size: Vec2(f32),
};

pub const Node = struct {
    Width: Sizing = .Fit,
    Height: Sizing = .Fit,
    Placement: Placement = .Flow,
    /// takes no room at all, and neither does anything under it: it and its gap are left out
    Collapsed: bool = false,
    /// null for a leaf. Only a container has children
    Container: ?Container = null,
    /// only read for a leaf
    Content: Content = .None,
    FirstChild: ?Index = null,
    NextSibling: ?Index = null,

    fn SizingOf(self: Node, axis: Axis) Sizing {
        return switch (axis) {
            .X => self.Width,
            .Y => self.Height,
        };
    }
};

pub const Result = struct {
    Size: Vec2(f32) = .{ .x = 0, .y = 0 },
    /// relative to the parent's center, which makes it the element's local translation
    Center: Vec2(f32) = .{ .x = 0, .y = 0 },
    /// whether layout decided where it goes. False for a collapsed element and everything under it, and for a
    /// root that isn't anchored: that one is sized, but stays wherever its own transform puts it
    Placed: bool = false,
    /// for a container that scrolls: how much room its children take with its padding, which can be more than its
    /// own size, and its scroll offset kept between 0 and how far they run past it
    ContentSize: Vec2(f32) = .{ .x = 0, .y = 0 },
    ScrollOffset: Vec2(f32) = .{ .x = 0, .y = 0 },
};

/// Lays out the tree under `root` and returns one result per node (nodes outside the tree are left at their
/// defaults). `root_area` is what the root sizes and anchors against, e.g. the screen for an overlay; null for a
/// root with nothing around it, e.g. a panel in the world. The results are allocated with `allocator`.
pub fn Solve(allocator: std.mem.Allocator, nodes: []const Node, root: Index, root_area: ?Vec2(f32)) ![]Result {
    const results = try allocator.alloc(Result, nodes.len);
    @memset(results, .{});

    var solver = Solver{ .mNodes = nodes, .mResults = results };
    solver.Run(root, root_area);
    return results;
}

const Solver = struct {
    mNodes: []const Node,
    mResults: []Result,

    fn Run(self: *Solver, root: Index, root_area: ?Vec2(f32)) void {
        if (self.mNodes[root].Collapsed) return;

        for ([_]Axis{ .X, .Y }) |axis| {
            self.Fit(root, axis);
            if (root_area) |area| self.SizeRootToArea(root, axis, Get(area, axis));
            self.Distribute(root, axis);
        }

        if (root_area) |area| {
            switch (self.mNodes[root].Placement) {
                .Anchored => |anchoring| {
                    self.mResults[root].Center = AnchoredCenter(anchoring, area, self.mResults[root].Size);
                    self.mResults[root].Placed = true;
                },
                .Flow => {},
            }
        }
        self.Place(root);
    }

    //---------------------------sizes---------------------------

    /// Bottom up: the size `index` would like along `axis`
    fn Fit(self: *Solver, index: Index, axis: Axis) void {
        const node = self.mNodes[index];
        if (node.Collapsed) return;

        var children = self.Children(index);
        while (children.Next()) |child| self.Fit(child, axis);

        var size: f32 = 0;
        if (node.Container) |container| {
            size = switch (container.Direction) {
                .Row, .Column => self.StackFit(index, container, axis),
                .Grid => self.GridFit(index, container, axis),
            };
        } else switch (node.Content) {
            .None => {},
            .Size => |content| size = Get(content, axis),
        }

        //fill and percent start from their fit size too: fill adds to it, and percent replaces it once the parent's
        //size is known (a root with no area keeps it)
        switch (node.SizingOf(axis)) {
            .Fixed => |fixed| size = fixed,
            .Fit, .Fill, .Percent => {},
        }
        self.SetSize(index, axis, size);
    }

    /// A row or column: its children end to end along its direction, and its biggest child across it
    fn StackFit(self: *Solver, index: Index, container: Container, axis: Axis) f32 {
        const along = container.Direction.MainAxis() == axis;
        var size: f32 = 0;
        var count: usize = 0;
        var flow = self.FlowChildren(index);
        while (flow.Next()) |child| {
            //a percent child sizes from this one, so this one can't size from it
            const child_size = switch (self.mNodes[child].SizingOf(axis)) {
                .Percent => 0,
                .Fixed, .Fit, .Fill => Get(self.mResults[child].Size, axis),
            };
            size = if (along) size + child_size else @max(size, child_size);
            count += 1;
        }
        if (along and count > 1) size += container.Gap * @as(f32, @floatFromInt(count - 1));
        return size + container.Padding.Along(axis);
    }

    /// A grid: across, its columns' worth of cells, or every cell in one row if it fits as many as there is room for.
    /// Down, its rows, which needs the column count and so its final width: every width is worked out before any
    /// height
    fn GridFit(self: *Solver, index: Index, container: Container, axis: Axis) f32 {
        const count = self.FlowCount(index);
        const lines = switch (axis) {
            .X => switch (container.Columns) {
                .Auto => count,
                .Count => |columns| @min(@max(columns, 1), count),
            },
            .Y => if (count == 0) 0 else std.math.divCeil(usize, count, self.GridColumns(index, container)) catch unreachable,
        };
        return Span(lines, self.CellSize(index, axis), container.Gap) + container.Padding.Along(axis);
    }

    /// The root against the root area, the way a parent treats a child across its direction
    fn SizeRootToArea(self: *Solver, root: Index, axis: Axis, area: f32) void {
        switch (self.mNodes[root].SizingOf(axis)) {
            .Percent => |fraction| self.SetSize(root, axis, fraction * area),
            .Fill => self.SetSize(root, axis, area),
            .Fixed, .Fit => {},
        }
    }

    /// Top down: `index` has its final size along `axis`, and hands it out to its children
    fn Distribute(self: *Solver, index: Index, axis: Axis) void {
        const node = self.mNodes[index];
        if (node.Collapsed) return;
        const container = node.Container orelse return;

        const size = Get(self.mResults[index].Size, axis);
        const inner = @max(size - container.Padding.Along(axis), 0);
        if (container.Direction == .Grid) {
            self.DistributeCells(index, axis);
        } else if (container.Direction.MainAxis() == axis) {
            self.DistributeAlong(index, axis, inner, container.Gap);
        } else {
            self.DistributeAcross(index, axis, inner);
        }

        //anchored children size against the whole of this one, the same rectangle they're pinned to
        var anchored = self.AnchoredChildren(index);
        while (anchored.Next()) |child| {
            switch (self.mNodes[child].SizingOf(axis)) {
                .Percent => |fraction| self.SetSize(child, axis, fraction * size),
                .Fill => self.SetSize(child, axis, size),
                .Fixed, .Fit => {},
            }
        }

        var children = self.Children(index);
        while (children.Next()) |child| self.Distribute(child, axis);
    }

    /// Along the container's direction: percents take their share, then whatever is left over goes to the
    /// children that fill, by weight. If nothing is left over they keep their fit size, and anything too big
    /// overflows
    fn DistributeAlong(self: *Solver, index: Index, axis: Axis, inner: f32, gap: f32) void {
        var used: f32 = 0;
        var count: usize = 0;
        var total_weight: f32 = 0;
        var flow = self.FlowChildren(index);
        while (flow.Next()) |child| {
            switch (self.mNodes[child].SizingOf(axis)) {
                .Percent => |fraction| self.SetSize(child, axis, fraction * inner),
                .Fill => |weight| total_weight += @max(weight, 0),
                .Fixed, .Fit => {},
            }
            used += Get(self.mResults[child].Size, axis);
            count += 1;
        }
        if (count > 1) used += gap * @as(f32, @floatFromInt(count - 1));

        const leftover = inner - used;
        if (leftover <= 0 or total_weight <= 0) return;

        flow = self.FlowChildren(index);
        while (flow.Next()) |child| {
            switch (self.mNodes[child].SizingOf(axis)) {
                .Fill => |weight| {
                    const size = Get(self.mResults[child].Size, axis);
                    self.SetSize(child, axis, size + leftover * @max(weight, 0) / total_weight);
                },
                .Fixed, .Fit, .Percent => {},
            }
        }
    }

    /// In a grid: children that fill take their whole cell, percents their share of it, and the rest keep their size
    fn DistributeCells(self: *Solver, index: Index, axis: Axis) void {
        const cell = self.CellSize(index, axis);
        var flow = self.FlowChildren(index);
        while (flow.Next()) |child| {
            switch (self.mNodes[child].SizingOf(axis)) {
                .Percent => |fraction| self.SetSize(child, axis, fraction * cell),
                .Fill => self.SetSize(child, axis, cell),
                .Fixed, .Fit => {},
            }
        }
    }

    /// Across the container's direction: children that fill take all of it, percents their share, and the rest
    /// keep their size
    fn DistributeAcross(self: *Solver, index: Index, axis: Axis, inner: f32) void {
        var flow = self.FlowChildren(index);
        while (flow.Next()) |child| {
            switch (self.mNodes[child].SizingOf(axis)) {
                .Percent => |fraction| self.SetSize(child, axis, fraction * inner),
                .Fill => self.SetSize(child, axis, inner),
                .Fixed, .Fit => {},
            }
        }
    }

    //-------------------------positions-------------------------

    /// Top down: where each child of `index` goes, relative to its center
    fn Place(self: *Solver, index: Index) void {
        const node = self.mNodes[index];
        if (node.Collapsed) return;
        const container = node.Container orelse return;
        const size = self.mResults[index].Size;

        //the inside of the container, around its center
        const left = -size.x / 2 + container.Padding.Left;
        const right = size.x / 2 - container.Padding.Right;
        const top = size.y / 2 - container.Padding.Top;
        const bottom = -size.y / 2 + container.Padding.Bottom;

        switch (container.Direction) {
            .Row, .Column => self.PlaceStack(index, container, left, right, top, bottom),
            .Grid => self.PlaceCells(index, container, left, top),
        }
        if (container.Scroll != .None) self.ApplyScroll(index, container);

        var anchored = self.AnchoredChildren(index);
        while (anchored.Next()) |child| {
            const anchoring = self.mNodes[child].Placement.Anchored;
            self.mResults[child].Center = AnchoredCenter(anchoring, size, self.mResults[child].Size);
            self.mResults[child].Placed = true;
        }

        var children = self.Children(index);
        while (children.Next()) |child| self.Place(child);
    }

    /// A row or column's children end to end from its start, each one aligned across it. The edges are the inside
    /// of the container, around its center
    fn PlaceStack(self: *Solver, index: Index, container: Container, left: f32, right: f32, top: f32, bottom: f32) void {
        const main_axis = container.Direction.MainAxis();
        var run: f32 = 0;
        var count: usize = 0;
        var flow = self.FlowChildren(index);
        while (flow.Next()) |child| {
            run += Get(self.mResults[child].Size, main_axis);
            count += 1;
        }
        if (count > 1) run += container.Gap * @as(f32, @floatFromInt(count - 1));

        const available = switch (container.Direction) {
            .Row => right - left,
            .Column => top - bottom,
            .Grid => unreachable,
        };
        //how far into the inside each child starts, measured from the start edge: the left for a row, the top for
        //a column
        var cursor: f32 = switch (container.MainAlign) {
            .Start => 0,
            .Center => (available - run) / 2,
        };
        //scrolled to, from its start
        if (container.Scroll.Along(main_axis)) cursor = @max(cursor, 0);

        flow = self.FlowChildren(index);
        while (flow.Next()) |child| {
            const child_size = self.mResults[child].Size;
            const center: Vec2(f32) = switch (container.Direction) {
                .Row => .{
                    .x = left + cursor + child_size.x / 2,
                    .y = if (container.CrossAlign == .Start or OverflowsScrolled(container, .Y, child_size.y, top - bottom))
                        top - child_size.y / 2
                    else
                        (top + bottom) / 2,
                },
                .Column => .{
                    .x = if (container.CrossAlign == .Start or OverflowsScrolled(container, .X, child_size.x, right - left))
                        left + child_size.x / 2
                    else
                        (left + right) / 2,
                    .y = top - cursor - child_size.y / 2,
                },
                .Grid => unreachable,
            };
            self.mResults[child].Center = center;
            self.mResults[child].Placed = true;
            cursor += Get(child_size, main_axis) + container.Gap;
        }
    }

    /// A grid's children into its cells, left to right and then down a row, each at its cell's top left. `left` and
    /// `top` are the inside of the grid's edges, around its center
    fn PlaceCells(self: *Solver, index: Index, container: Container, left: f32, top: f32) void {
        const columns = self.GridColumns(index, container);
        const cell = Vec2(f32){ .x = self.CellSize(index, .X), .y = self.CellSize(index, .Y) };
        var i: usize = 0;
        var flow = self.FlowChildren(index);
        while (flow.Next()) |child| : (i += 1) {
            const column: f32 = @floatFromInt(i % columns);
            const row: f32 = @floatFromInt(i / columns);
            const child_size = self.mResults[child].Size;
            self.mResults[child].Center = .{
                .x = left + column * (cell.x + container.Gap) + child_size.x / 2,
                .y = top - row * (cell.y + container.Gap) - child_size.y / 2,
            };
            self.mResults[child].Placed = true;
        }
    }

    //--------------------------scrolling--------------------------

    /// Works out how much room a scrolling container's children take, keeps its offset in range, and moves its flow
    /// children by it. Anchored children stay put: they are pinned to the container, like a corner button
    fn ApplyScroll(self: *Solver, index: Index, container: Container) void {
        const size = self.mResults[index].Size;
        const content = Vec2(f32){ .x = self.ContentAlong(index, container, .X), .y = self.ContentAlong(index, container, .Y) };
        const offset = Vec2(f32){
            .x = if (container.Scroll.Along(.X)) std.math.clamp(container.ScrollOffset.x, 0, @max(content.x - size.x, 0)) else 0,
            .y = if (container.Scroll.Along(.Y)) std.math.clamp(container.ScrollOffset.y, 0, @max(content.y - size.y, 0)) else 0,
        };
        self.mResults[index].ContentSize = content;
        self.mResults[index].ScrollOffset = offset;

        var flow = self.FlowChildren(index);
        while (flow.Next()) |child| {
            //scrolling right shows what is further right, so the children go left; scrolling down moves them up
            self.mResults[child].Center.x -= offset.x;
            self.mResults[child].Center.y += offset.y;
        }
    }

    /// The room the container's children take along `axis`, with its padding: what it would fit to, from their
    /// final sizes
    fn ContentAlong(self: *Solver, index: Index, container: Container, axis: Axis) f32 {
        return switch (container.Direction) {
            .Row, .Column => self.StackFit(index, container, axis),
            .Grid => self.GridFit(index, container, axis),
        };
    }

    //---------------------------grids---------------------------

    /// A grid's cell size along `axis`: its biggest child's. A percent child sizes from its cell, so the cell can't
    /// size from it
    fn CellSize(self: *Solver, index: Index, axis: Axis) f32 {
        var cell: f32 = 0;
        var flow = self.FlowChildren(index);
        while (flow.Next()) |child| {
            switch (self.mNodes[child].SizingOf(axis)) {
                .Percent => {},
                .Fixed, .Fit, .Fill => cell = @max(cell, Get(self.mResults[child].Size, axis)),
            }
        }
        return cell;
    }

    /// How many columns a grid has, from its final width: never fewer than one, never more than it has children
    fn GridColumns(self: *Solver, index: Index, container: Container) usize {
        const count = @max(self.FlowCount(index), 1);
        const columns: usize = switch (container.Columns) {
            .Count => |columns| columns,
            .Auto => blk: {
                const inner = self.mResults[index].Size.x - container.Padding.Along(.X);
                const step = self.CellSize(index, .X) + container.Gap;
                if (step <= 0) break :blk count;
                //n cells take n steps less one gap
                break :blk @intFromFloat(@max(@floor((inner + container.Gap) / step), 0));
            },
        };
        return std.math.clamp(columns, 1, count);
    }

    fn FlowCount(self: *Solver, index: Index) usize {
        var count: usize = 0;
        var flow = self.FlowChildren(index);
        while (flow.Next()) |_| count += 1;
        return count;
    }

    //--------------------------helpers--------------------------

    fn SetSize(self: *Solver, index: Index, axis: Axis, size: f32) void {
        Set(&self.mResults[index].Size, axis, size);
    }

    const Filter = enum { All, Flow, Anchored };

    const ChildIterator = struct {
        mNodes: []const Node,
        mNext: ?Index,
        mFilter: Filter,

        fn Next(self: *ChildIterator) ?Index {
            while (self.mNext) |child| {
                const node = self.mNodes[child];
                self.mNext = node.NextSibling;
                const keep = switch (self.mFilter) {
                    .All => true,
                    .Flow => !node.Collapsed and node.Placement == .Flow,
                    .Anchored => !node.Collapsed and node.Placement == .Anchored,
                };
                if (keep) return child;
            }
            return null;
        }
    };

    fn Children(self: *Solver, index: Index) ChildIterator {
        return self.Iterate(index, .All);
    }

    /// The children stacked by the container, collapsed ones left out
    fn FlowChildren(self: *Solver, index: Index) ChildIterator {
        return self.Iterate(index, .Flow);
    }

    /// The children pinned to a point of it, collapsed ones left out
    fn AnchoredChildren(self: *Solver, index: Index) ChildIterator {
        return self.Iterate(index, .Anchored);
    }

    fn Iterate(self: *const Solver, index: Index, filter: Filter) ChildIterator {
        const node = self.mNodes[index];
        //a leaf's children would be ignored by every pass, better to hear about it
        std.debug.assert(node.Container != null or node.FirstChild == null);
        return .{ .mNodes = self.mNodes, .mNext = node.FirstChild, .mFilter = filter };
    }
};

/// The center of an element of `size` pinned by `anchoring` to a rectangle of `parent_size`, both around the
/// rectangle's center
pub fn AnchoredCenter(anchoring: Anchoring, parent_size: Vec2(f32), size: Vec2(f32)) Vec2(f32) {
    return .{
        .x = anchoring.Anchor.x * parent_size.x / 2 - anchoring.Pivot.x * size.x / 2 + anchoring.Offset.x,
        .y = anchoring.Anchor.y * parent_size.y / 2 - anchoring.Pivot.y * size.y / 2 + anchoring.Offset.y,
    };
}

/// Whether a child `child_size` long across a container's `room` overflows it along `axis` while it scrolls that
/// way: then it starts at the start edge instead of being centered, so all of it can be scrolled to
fn OverflowsScrolled(container: Container, axis: Axis, child_size: f32, room: f32) bool {
    return container.Scroll.Along(axis) and child_size > room;
}

/// How long `count` cells of `cell` take end to end, with `gap` between each
fn Span(count: usize, cell: f32, gap: f32) f32 {
    if (count == 0) return 0;
    const n: f32 = @floatFromInt(count);
    return n * cell + (n - 1) * gap;
}

fn Get(v: Vec2(f32), axis: Axis) f32 {
    return switch (axis) {
        .X => v.x,
        .Y => v.y,
    };
}

fn Set(v: *Vec2(f32), axis: Axis, value: f32) void {
    switch (axis) {
        .X => v.x = value,
        .Y => v.y = value,
    }
}
