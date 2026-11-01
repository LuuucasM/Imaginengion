//! What `zig build game` runs last, once the game is built: prints which of its files it needs, what objects are saved in
//! them and what's wrong with what's saved (GameBuild/ProjectWalk.zig, ForestChecks.zig), and clears what earlier builds left
//! in the game's folder. The game is already built, so whatever goes wrong here is printed and the build carries on.
//! GameReport <project folder> <engine folder> <game name> <game folder> [trees], the project file being <game name>.imprj.
//! With trees, it first prints the whole forest
const std = @import("std");
const ForestChecks = @import("Imaginengion/GameBuild/ForestChecks.zig");
const ProjectWalk = @import("Imaginengion/GameBuild/ProjectWalk.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &stdout.interface;

    Report(arena, init.io, args[1], args[2], args[3], args[4], args.len > 5, out) catch |err| {
        try out.print("Couldn't work out which files {s} needs: {s}\n", .{ args[3], @errorName(err) });
    };
    try out.flush();
}

fn Report(arena: std.mem.Allocator, io: std.Io, project_path: []const u8, engine_path: []const u8, game_name: []const u8, game_path: []const u8, trees: bool, out: *std.Io.Writer) !void {
    const project_file = try std.fmt.allocPrint(arena, "{s}.imprj", .{game_name});
    const result = try ProjectWalk.WalkProject(arena, io, project_path, engine_path, project_file);
    const not_needed = try ProjectWalk.FindNotNeeded(arena, io, project_path, engine_path, &result);
    const checks = try ForestChecks.Run(arena, &result);
    if (trees) try ProjectWalk.WriteForest(out, &result);
    try ProjectWalk.WriteReport(out, game_name, &result, &not_needed);
    try ForestChecks.WriteChecks(out, &checks);

    const removed = ProjectWalk.RemoveLeftovers(arena, io, game_path, game_name, &result) catch |err| {
        try out.print("Couldn't clear what earlier builds left in the game's folder: {s}\n", .{@errorName(err)});
        return;
    };
    if (removed > 0) try out.print("Removed {d} files earlier builds left in the game's folder\n", .{removed});
}
