//! The layout rules on plain trees, no engine needed. Run with `zig build test`.
const std = @import("std");
const Layout = @import("../../UI/Layout.zig");
const Node = Layout.Node;
const Index = Layout.Index;
const Vec2 = @import("../../Math/MathTypes.zig").Vec2;

const eps: f32 = 0.001;

/// Builds a tree node by node, each added as the last child of its parent
const Tree = struct {
    mNodes: std.ArrayList(Node) = .empty,
    mLastChild: std.ArrayList(?Index) = .empty,

    fn Deinit(self: *Tree) void {
        self.mNodes.deinit(std.testing.allocator);
        self.mLastChild.deinit(std.testing.allocator);
    }

    fn Add(self: *Tree, parent: ?Index, node: Node) !Index {
        const index: Index = @intCast(self.mNodes.items.len);
        try self.mNodes.append(std.testing.allocator, node);
        try self.mLastChild.append(std.testing.allocator, null);
        if (parent) |p| {
            if (self.mLastChild.items[p]) |last| {
                self.mNodes.items[last].NextSibling = index;
            } else {
                self.mNodes.items[p].FirstChild = index;
            }
            self.mLastChild.items[p] = index;
        }
        return index;
    }

    fn Solve(self: *Tree, root_area: ?Vec2(f32)) ![]Layout.Result {
        return Layout.Solve(std.testing.allocator, self.mNodes.items, 0, root_area);
    }
};

fn Box(x: f32, y: f32) Layout.Content {
    return .{ .Size = .{ .x = x, .y = y } };
}

fn V(x: f32, y: f32) Vec2(f32) {
    return .{ .x = x, .y = y };
}

fn ExpectVec(expected: Vec2(f32), actual: Vec2(f32)) !void {
    std.testing.expectApproxEqAbs(expected.x, actual.x, eps) catch |err| {
        std.debug.print("expected {d}, {d} got {d}, {d}\n", .{ expected.x, expected.y, actual.x, actual.y });
        return err;
    };
    std.testing.expectApproxEqAbs(expected.y, actual.y, eps) catch |err| {
        std.debug.print("expected {d}, {d} got {d}, {d}\n", .{ expected.x, expected.y, actual.x, actual.y });
        return err;
    };
}

//-------------------------------sizes-------------------------------

test "fixed sizes pass through" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const root = try tree.Add(null, .{ .Width = .{ .Fixed = 400 }, .Height = .{ .Fixed = 300 }, .Container = .{} });
    const fixed = try tree.Add(root, .{ .Width = .{ .Fixed = 100 }, .Height = .{ .Fixed = 50 } });
    //a fixed size wins over what it holds
    const boxed = try tree.Add(root, .{ .Width = .{ .Fixed = 5 }, .Content = Box(30, 20) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    try ExpectVec(V(400, 300), results[root].Size);
    try ExpectVec(V(100, 50), results[fixed].Size);
    try ExpectVec(V(5, 20), results[boxed].Size);
}

test "a fit leaf is the size of what it holds" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const root = try tree.Add(null, .{ .Container = .{} });
    const boxed = try tree.Add(root, .{ .Content = Box(30, 20) });
    const empty = try tree.Add(root, .{});

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    try ExpectVec(V(30, 20), results[boxed].Size);
    try ExpectVec(V(0, 0), results[empty].Size);
}

test "a fit row adds up its children, gaps and padding, and is as tall as its tallest" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const row = try tree.Add(null, .{ .Container = .{
        .Direction = .Row,
        .Gap = 5,
        .Padding = .{ .Left = 2, .Right = 3, .Top = 4, .Bottom = 1 },
    } });
    _ = try tree.Add(row, .{ .Content = Box(10, 20) });
    _ = try tree.Add(row, .{ .Content = Box(30, 5) });
    _ = try tree.Add(row, .{ .Content = Box(20, 8) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    //60 of children, two gaps of 5, 5 of padding; 20 tall plus 5 of padding
    try ExpectVec(V(75, 25), results[row].Size);
}

test "a fit column adds up its children, gaps and padding, and is as wide as its widest" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const column = try tree.Add(null, .{ .Container = .{ .Direction = .Column, .Gap = 10, .Padding = .All(5) } });
    _ = try tree.Add(column, .{ .Content = Box(10, 20) });
    _ = try tree.Add(column, .{ .Content = Box(40, 30) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    try ExpectVec(V(50, 70), results[column].Size);
}

test "a fill child takes what's left, and several share it by weight" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const row = try tree.Add(null, .{ .Width = .{ .Fixed = 100 }, .Container = .{ .Direction = .Row } });
    const fixed = try tree.Add(row, .{ .Width = .{ .Fixed = 20 } });
    const one = try tree.Add(row, .{ .Width = .{ .Fill = 1 } });
    const three = try tree.Add(row, .{ .Width = .{ .Fill = 3 } });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    try std.testing.expectApproxEqAbs(@as(f32, 20), results[fixed].Size.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 20), results[one].Size.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 60), results[three].Size.x, eps);
}

test "equal fill weights split a row equally, like x, y and z fields" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const row = try tree.Add(null, .{ .Width = .{ .Fixed = 310 }, .Container = .{ .Direction = .Row, .Gap = 5 } });
    const x = try tree.Add(row, .{ .Width = .{ .Fill = 1 } });
    const y = try tree.Add(row, .{ .Width = .{ .Fill = 1 } });
    const z = try tree.Add(row, .{ .Width = .{ .Fill = 1 } });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    for ([_]Index{ x, y, z }) |field| {
        try std.testing.expectApproxEqAbs(@as(f32, 100), results[field].Size.x, eps);
    }
    try std.testing.expectApproxEqAbs(@as(f32, 105), results[z].Center.x - results[y].Center.x, eps);
}

test "filling adds to a child's fit size rather than replacing it" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const row = try tree.Add(null, .{ .Width = .{ .Fixed = 100 }, .Container = .{ .Direction = .Row } });
    const small = try tree.Add(row, .{ .Width = .{ .Fill = 1 }, .Content = Box(10, 10) });
    const big = try tree.Add(row, .{ .Width = .{ .Fill = 1 }, .Content = Box(30, 10) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    //60 left over, 30 each
    try std.testing.expectApproxEqAbs(@as(f32, 40), results[small].Size.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 60), results[big].Size.x, eps);
}

test "a percent child is a share of the inside of its parent" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const row = try tree.Add(null, .{ .Width = .{ .Fixed = 200 }, .Height = .{ .Fixed = 100 }, .Container = .{
        .Direction = .Row,
        .Padding = .{ .Left = 10, .Right = 10, .Top = 20, .Bottom = 20 },
    } });
    const half = try tree.Add(row, .{ .Width = .{ .Percent = 0.5 }, .Height = .{ .Percent = 0.5 } });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    try ExpectVec(V(90, 30), results[half].Size);
}

test "a percent child doesn't count towards a parent that fits its children" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const row = try tree.Add(null, .{ .Container = .{ .Direction = .Row } });
    _ = try tree.Add(row, .{ .Content = Box(40, 10) });
    const half = try tree.Add(row, .{ .Width = .{ .Percent = 0.5 } });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    try std.testing.expectApproxEqAbs(@as(f32, 40), results[row].Size.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 20), results[half].Size.x, eps);
}

test "children too big for their parent overflow rather than being squeezed" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const row = try tree.Add(null, .{ .Width = .{ .Fixed = 100 }, .Container = .{ .Direction = .Row } });
    const a = try tree.Add(row, .{ .Content = Box(80, 10) });
    const b = try tree.Add(row, .{ .Width = .{ .Fill = 1 }, .Content = Box(80, 10) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    //nothing left over for the fill child to take, and nobody shrinks
    try std.testing.expectApproxEqAbs(@as(f32, 80), results[a].Size.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 80), results[b].Size.x, eps);
    //the second starts where the first ends, past the right edge of the row
    try std.testing.expectApproxEqAbs(@as(f32, 70), results[b].Center.x, eps);
}

test "across its parent, a fill child fills it and the others keep their size" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const column = try tree.Add(null, .{ .Width = .{ .Fixed = 100 }, .Container = .{
        .Direction = .Column,
        .Padding = .{ .Left = 5, .Right = 5 },
    } });
    //a list row, as wide as the list
    const row = try tree.Add(column, .{ .Width = .{ .Fill = 1 }, .Content = Box(30, 10) });
    const fit = try tree.Add(column, .{ .Content = Box(30, 10) });
    const fixed = try tree.Add(column, .{ .Width = .{ .Fixed = 30 } });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    try std.testing.expectApproxEqAbs(@as(f32, 90), results[row].Size.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 30), results[fit].Size.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 30), results[fixed].Size.x, eps);
}

//-----------------------------positions------------------------------

test "a column stacks from the top down, inside its padding and with its gaps" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const column = try tree.Add(null, .{ .Width = .{ .Fixed = 100 }, .Height = .{ .Fixed = 100 }, .Container = .{
        .Direction = .Column,
        .Padding = .All(10),
        .Gap = 5,
    } });
    const first = try tree.Add(column, .{ .Content = Box(20, 10) });
    const second = try tree.Add(column, .{ .Content = Box(20, 20) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    //the inside's top is 40, its left -40, and Start puts children at the top left
    try ExpectVec(V(-30, 35), results[first].Center);
    try ExpectVec(V(-30, 15), results[second].Center);
    try std.testing.expect(results[first].Placed and results[second].Placed);
}

test "a column's children can be centered along and across it" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const column = try tree.Add(null, .{ .Width = .{ .Fixed = 100 }, .Height = .{ .Fixed = 100 }, .Container = .{
        .Direction = .Column,
        .Padding = .All(10),
        .Gap = 5,
        .MainAlign = .Center,
        .CrossAlign = .Center,
    } });
    const first = try tree.Add(column, .{ .Content = Box(20, 10) });
    const second = try tree.Add(column, .{ .Content = Box(20, 20) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    //the run is 35 tall, so it goes from 17.5 down to -17.5
    try ExpectVec(V(0, 12.5), results[first].Center);
    try ExpectVec(V(0, -7.5), results[second].Center);
}

test "a row runs left to right, centered along and across it" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const row = try tree.Add(null, .{ .Width = .{ .Fixed = 100 }, .Height = .{ .Fixed = 40 }, .Container = .{
        .Direction = .Row,
        .MainAlign = .Center,
        .CrossAlign = .Center,
    } });
    const left = try tree.Add(row, .{ .Content = Box(20, 10) });
    const right = try tree.Add(row, .{ .Content = Box(20, 30) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    try ExpectVec(V(-10, 0), results[left].Center);
    try ExpectVec(V(10, 0), results[right].Center);
}

test "across a row, start is the top" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const row = try tree.Add(null, .{ .Width = .{ .Fixed = 100 }, .Height = .{ .Fixed = 40 }, .Container = .{ .Direction = .Row } });
    const child = try tree.Add(row, .{ .Content = Box(20, 10) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    try ExpectVec(V(-40, 15), results[child].Center);
}

//------------------------------anchoring------------------------------

test "an anchored child is pinned to a point of its parent's whole rectangle" {
    var tree: Tree = .{};
    defer tree.Deinit();
    //the padding doesn't move anchored children
    const panel = try tree.Add(null, .{ .Width = .{ .Fixed = 200 }, .Height = .{ .Fixed = 100 }, .Container = .{ .Padding = .All(10) } });
    //a close button in the top right corner, 5 in from both edges
    const close = try tree.Add(panel, .{ .Content = Box(20, 10), .Placement = .{ .Anchored = .{
        .Anchor = V(1, 1),
        .Pivot = V(1, 1),
        .Offset = V(-5, -5),
    } } });
    //its bottom left corner on the middle
    const marker = try tree.Add(panel, .{ .Content = Box(20, 10), .Placement = .{ .Anchored = .{ .Pivot = V(-1, -1) } } });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    try ExpectVec(V(85, 40), results[close].Center);
    try ExpectVec(V(10, 5), results[marker].Center);
}

test "anchored children take no room, and size against the parent's whole rectangle" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const column = try tree.Add(null, .{ .Container = .{ .Padding = .All(10) } });
    _ = try tree.Add(column, .{ .Content = Box(30, 30) });
    const backdrop = try tree.Add(column, .{ .Width = .{ .Fill = 1 }, .Height = .{ .Percent = 1 }, .Placement = .{ .Anchored = .{} } });
    _ = try tree.Add(column, .{ .Content = Box(500, 500), .Placement = .{ .Anchored = .{} } });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    //the big anchored one doesn't make the column any bigger
    try ExpectVec(V(50, 50), results[column].Size);
    //and the backdrop covers the padding too
    try ExpectVec(V(50, 50), results[backdrop].Size);
    try ExpectVec(V(0, 0), results[backdrop].Center);
}

//------------------------------collapsed------------------------------

test "a collapsed child takes no room and no gap, and isn't placed" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const column = try tree.Add(null, .{ .Container = .{ .Gap = 10 } });
    const first = try tree.Add(column, .{ .Content = Box(10, 10) });
    const hidden = try tree.Add(column, .{ .Content = Box(10, 10), .Collapsed = true });
    const last = try tree.Add(column, .{ .Content = Box(10, 10) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    try std.testing.expectApproxEqAbs(@as(f32, 30), results[column].Size.y, eps);
    try std.testing.expect(!results[hidden].Placed);
    //right under the first one
    try std.testing.expectApproxEqAbs(results[first].Center.y - 20, results[last].Center.y, eps);
}

//--------------------------------roots--------------------------------

test "a root anchored in the root area is sized and placed against it" {
    var tree: Tree = .{};
    defer tree.Deinit();
    //half the screen each way, in the top left
    const root = try tree.Add(null, .{
        .Width = .{ .Percent = 0.5 },
        .Height = .{ .Percent = 0.5 },
        .Placement = .{ .Anchored = .{ .Anchor = V(-1, 1), .Pivot = V(-1, 1) } },
        .Container = .{},
    });

    const results = try tree.Solve(V(1000, 500));
    defer std.testing.allocator.free(results);

    try ExpectVec(V(500, 250), results[root].Size);
    try ExpectVec(V(-250, 125), results[root].Center);
    try std.testing.expect(results[root].Placed);
}

test "a root that fills takes the whole root area" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const root = try tree.Add(null, .{ .Width = .{ .Fill = 1 }, .Height = .{ .Fill = 1 }, .Container = .{} });

    const results = try tree.Solve(V(1000, 500));
    defer std.testing.allocator.free(results);

    try ExpectVec(V(1000, 500), results[root].Size);
}

test "a root that isn't anchored is sized but left where it is" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const root = try tree.Add(null, .{ .Width = .{ .Fixed = 300 }, .Height = .{ .Fixed = 200 }, .Container = .{} });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    try ExpectVec(V(300, 200), results[root].Size);
    try std.testing.expect(!results[root].Placed);
}

//----------------------------all together-----------------------------

test "Pong's menu: a centered column of a title and two buttons with labels" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const menu = try tree.Add(null, .{
        .Placement = .{ .Anchored = .{} },
        .Container = .{ .Direction = .Column, .Padding = .All(40), .Gap = 20, .CrossAlign = .Center },
    });
    const title = try tree.Add(menu, .{ .Content = Box(200, 80) });
    const button: Node = .{ .Width = .{ .Fixed = 300 }, .Container = .{
        .Direction = .Row,
        .Padding = .All(12),
        .MainAlign = .Center,
        .CrossAlign = .Center,
    } };
    const play = try tree.Add(menu, button);
    const play_label = try tree.Add(play, .{ .Content = Box(60, 32) });
    const quit = try tree.Add(menu, button);
    _ = try tree.Add(quit, .{ .Content = Box(60, 32) });

    const results = try tree.Solve(V(1920, 1080));
    defer std.testing.allocator.free(results);

    try ExpectVec(V(380, 312), results[menu].Size);
    try ExpectVec(V(0, 0), results[menu].Center);
    try ExpectVec(V(300, 56), results[play].Size);
    try ExpectVec(V(0, 76), results[title].Center);
    try ExpectVec(V(0, -12), results[play].Center);
    try ExpectVec(V(0, -88), results[quit].Center);
    try ExpectVec(V(0, 0), results[play_label].Center);
}

test "an inspector row: a fixed label, then three equal fields filling the rest" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const row = try tree.Add(null, .{ .Width = .{ .Fixed = 400 }, .Container = .{ .Direction = .Row, .Gap = 4, .CrossAlign = .Center } });
    const label = try tree.Add(row, .{ .Width = .{ .Fixed = 100 }, .Content = Box(70, 16) });
    var fields: [3]Index = undefined;
    for (&fields) |*field| field.* = try tree.Add(row, .{ .Width = .{ .Fill = 1 }, .Content = Box(0, 20) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    //400 less the label and three gaps leaves 288, 96 each
    for (fields) |field| try std.testing.expectApproxEqAbs(@as(f32, 96), results[field].Size.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 20), results[row].Size.y, eps);
    //the last field ends on the row's right edge
    try std.testing.expectApproxEqAbs(@as(f32, 200), results[fields[2]].Center.x + 48, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -150), results[label].Center.x, eps);
}

//-------------------------------grids-------------------------------

test "a grid fits as many cells across as its width has room for, then wraps" {
    var tree: Tree = .{};
    defer tree.Deinit();
    //30 wide cells 10 apart: 100 has room for two (30 + 10 + 30), not three (110)
    const grid = try tree.Add(null, .{ .Width = .{ .Fixed = 100 }, .Container = .{ .Direction = .Grid, .Gap = 10 } });
    var cells: [5]Index = undefined;
    for (&cells) |*cell| cell.* = try tree.Add(grid, .{ .Content = Box(30, 20) });

    var results = try tree.Solve(null);
    //three rows of 20, 10 apart
    try ExpectVec(V(100, 80), results[grid].Size);
    //from the top left, left to right and then down
    try ExpectVec(V(-35, 30), results[cells[0]].Center);
    try ExpectVec(V(5, 30), results[cells[1]].Center);
    try ExpectVec(V(-35, 0), results[cells[2]].Center);
    try ExpectVec(V(5, 0), results[cells[3]].Center);
    try ExpectVec(V(-35, -30), results[cells[4]].Center);
    std.testing.allocator.free(results);

    //wider: three across, two rows
    tree.mNodes.items[grid].Width = .{ .Fixed = 130 };
    results = try tree.Solve(null);
    defer std.testing.allocator.free(results);
    try ExpectVec(V(130, 50), results[grid].Size);
    try ExpectVec(V(-50, 15), results[cells[0]].Center);
    try ExpectVec(V(30, 15), results[cells[2]].Center);
    try ExpectVec(V(-50, -15), results[cells[3]].Center);
}

test "a grid with a set number of columns fits them, or fewer if it has fewer children" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const grid = try tree.Add(null, .{ .Container = .{ .Direction = .Grid, .Columns = .{ .Count = 3 }, .Gap = 5, .Padding = .All(10) } });
    var cells: [4]Index = undefined;
    for (&cells) |*cell| cell.* = try tree.Add(grid, .{ .Width = .{ .Fixed = 20 }, .Height = .{ .Fixed = 10 } });

    var results = try tree.Solve(null);
    //three cells and two gaps across, two rows down, and the padding around
    try ExpectVec(V(90, 45), results[grid].Size);
    //the fourth starts the second row
    try ExpectVec(V(-25, 7.5), results[cells[0]].Center);
    try ExpectVec(V(25, 7.5), results[cells[2]].Center);
    try ExpectVec(V(-25, -7.5), results[cells[3]].Center);
    std.testing.allocator.free(results);

    tree.mNodes.items[cells[1]].NextSibling = null;
    results = try tree.Solve(null);
    defer std.testing.allocator.free(results);
    try ExpectVec(V(65, 30), results[grid].Size);
}

test "every cell is the size of the biggest child, and a child that fills takes a whole cell" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const grid = try tree.Add(null, .{ .Container = .{ .Direction = .Grid, .Columns = .{ .Count = 2 } } });
    const wide = try tree.Add(grid, .{ .Content = Box(30, 10) });
    const tall = try tree.Add(grid, .{ .Content = Box(10, 40) });
    const filler = try tree.Add(grid, .{ .Width = .{ .Fill = 1 }, .Height = .{ .Fill = 1 } });
    const half = try tree.Add(grid, .{ .Width = .{ .Percent = 0.5 }, .Content = Box(0, 4) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);

    //30 x 40 cells, two by two
    try ExpectVec(V(60, 80), results[grid].Size);
    try ExpectVec(V(30, 10), results[wide].Size);
    try ExpectVec(V(30, 40), results[filler].Size);
    try ExpectVec(V(15, 4), results[half].Size);
    //each at its cell's top left
    try ExpectVec(V(-15, 35), results[wide].Center);
    try ExpectVec(V(5, 20), results[tall].Center);
    try ExpectVec(V(-15, -20), results[filler].Center);
    try ExpectVec(V(7.5, -2), results[half].Center);
}

test "a grid that fits its children with no set columns is one row" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const grid = try tree.Add(null, .{ .Container = .{ .Direction = .Grid, .Gap = 2 } });
    for (0..3) |_| _ = try tree.Add(grid, .{ .Content = Box(10, 10) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);
    try ExpectVec(V(34, 10), results[grid].Size);
}

test "a grid filling its parent works out its columns from the width it is given" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const column = try tree.Add(null, .{ .Width = .{ .Fixed = 100 }, .Container = .{ .Direction = .Column } });
    const grid = try tree.Add(column, .{ .Width = .{ .Fill = 1 }, .Container = .{ .Direction = .Grid } });
    for (0..4) |_| _ = try tree.Add(grid, .{ .Content = Box(30, 10) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);
    //three 30 wide cells fit in 100, so the fourth wraps
    try ExpectVec(V(100, 20), results[grid].Size);
    try ExpectVec(V(100, 20), results[column].Size);
}

test "a collapsed child takes no cell" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const grid = try tree.Add(null, .{ .Container = .{ .Direction = .Grid, .Columns = .{ .Count = 2 } } });
    const first = try tree.Add(grid, .{ .Content = Box(10, 10) });
    _ = try tree.Add(grid, .{ .Collapsed = true, .Content = Box(10, 10) });
    const third = try tree.Add(grid, .{ .Content = Box(10, 10) });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);
    try ExpectVec(V(20, 10), results[grid].Size);
    try ExpectVec(V(-5, 0), results[first].Center);
    try ExpectVec(V(5, 0), results[third].Center);
}

//-----------------------------scrolling-----------------------------

test "a scrolling container moves its children by its offset, kept between 0 and how far they run past it" {
    var tree: Tree = .{};
    defer tree.Deinit();
    //100 x 50, three 30 tall rows: 90 of content, so it scrolls up to 40
    const list = try tree.Add(null, .{
        .Width = .{ .Fixed = 100 },
        .Height = .{ .Fixed = 50 },
        .Container = .{ .Direction = .Column, .Scroll = .Vertical, .ScrollOffset = V(10, 20) },
    });
    var rows: [3]Index = undefined;
    for (&rows) |*row| row.* = try tree.Add(list, .{ .Width = .{ .Fixed = 100 }, .Height = .{ .Fixed = 30 } });

    var results = try tree.Solve(null);
    try ExpectVec(V(100, 90), results[list].ContentSize);
    //it doesn't scroll sideways, so that part of the offset is dropped
    try ExpectVec(V(0, 20), results[list].ScrollOffset);
    //scrolled down 20: everything 20 higher than it would be
    try ExpectVec(V(0, 30), results[rows[0]].Center);
    try ExpectVec(V(0, -30), results[rows[2]].Center);
    std.testing.allocator.free(results);

    tree.mNodes.items[list].Container.?.ScrollOffset = V(0, 100);
    results = try tree.Solve(null);
    try ExpectVec(V(0, 40), results[list].ScrollOffset);
    //the last row's bottom on the list's bottom
    try ExpectVec(V(0, -10), results[rows[2]].Center);
    std.testing.allocator.free(results);

    tree.mNodes.items[list].Container.?.ScrollOffset = V(0, -5);
    results = try tree.Solve(null);
    defer std.testing.allocator.free(results);
    try ExpectVec(V(0, 0), results[list].ScrollOffset);
    try ExpectVec(V(0, 10), results[rows[0]].Center);
}

test "a Fill container that scrolls stays the room it is given instead of growing to hold its children" {
    var tree: Tree = .{};
    defer tree.Deinit();
    //a 100 tall window: a 20 tall title, and under it content that fills the rest and scrolls its three 30 tall rows
    const window = try tree.Add(null, .{
        .Width = .{ .Fixed = 100 },
        .Height = .{ .Fixed = 100 },
        .Container = .{ .Direction = .Column },
    });
    _ = try tree.Add(window, .{ .Width = .{ .Fill = 1 }, .Height = .{ .Fixed = 20 } });
    const content = try tree.Add(window, .{
        .Width = .{ .Fill = 1 },
        .Height = .{ .Fill = 1 },
        .Container = .{ .Direction = .Column, .Scroll = .Vertical, .Padding = .{ .Top = 5, .Bottom = 5 } },
    });
    for (0..3) |_| _ = try tree.Add(content, .{ .Width = .{ .Fixed = 100 }, .Height = .{ .Fixed = 30 } });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);
    //80 of room, not 90 of rows plus padding: the rest scrolls
    try ExpectVec(V(100, 80), results[content].Size);
    try ExpectVec(V(100, 100), results[content].ContentSize);
    try ExpectVec(V(100, 100), results[window].Size);
}

test "what overflows a scrolling container starts at its start edge, even when centered" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const list = try tree.Add(null, .{
        .Width = .{ .Fixed = 100 },
        .Height = .{ .Fixed = 50 },
        .Container = .{ .Direction = .Column, .MainAlign = .Center, .CrossAlign = .Center, .Scroll = .Both },
    });
    const wide = try tree.Add(list, .{ .Width = .{ .Fixed = 150 }, .Height = .{ .Fixed = 30 } });
    const narrow = try tree.Add(list, .{ .Width = .{ .Fixed = 10 }, .Height = .{ .Fixed = 30 } });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);
    try ExpectVec(V(150, 60), results[list].ContentSize);
    //60 of rows in 50 start at the top, and the 150 wide row at the left edge; the narrow one still centers
    try ExpectVec(V(25, 10), results[wide].Center);
    try ExpectVec(V(0, -20), results[narrow].Center);
}

test "a scrolling container's anchored children stay pinned where they are" {
    var tree: Tree = .{};
    defer tree.Deinit();
    const list = try tree.Add(null, .{
        .Width = .{ .Fixed = 100 },
        .Height = .{ .Fixed = 50 },
        .Container = .{ .Direction = .Column, .Scroll = .Vertical, .ScrollOffset = V(0, 20) },
    });
    for (0..3) |_| _ = try tree.Add(list, .{ .Width = .{ .Fixed = 100 }, .Height = .{ .Fixed = 30 } });
    const corner = try tree.Add(list, .{
        .Width = .{ .Fixed = 10 },
        .Height = .{ .Fixed = 10 },
        .Placement = .{ .Anchored = .{ .Anchor = V(1, 1), .Pivot = V(1, 1) } },
    });

    const results = try tree.Solve(null);
    defer std.testing.allocator.free(results);
    try ExpectVec(V(45, 20), results[corner].Center);
}
