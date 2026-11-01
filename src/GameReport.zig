//! What `zig build game` runs after building a game: prints which of its files it needs, what objects are saved in them and
//! what's wrong with what's saved (GameBuild/ProjectWalk.zig, ForestChecks.zig). It only reports, so whatever goes wrong
//! here is printed and the build carries on.
//! GameReport <project folder> <engine folder> <game name> [trees], the project file being <game name>.imprj. With trees,
//! it first prints the whole forest
const std = @import("std");
const ForestChecks = @import("Imaginengion/GameBuild/ForestChecks.zig");
const ProjectWalk = @import("Imaginengion/GameBuild/ProjectWalk.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &stdout.interface;

    Report(arena, init.io, args[1], args[2], args[3], args.len > 4, out) catch |err| {
        try out.print("Couldn't work out which files {s} needs: {s}\n", .{ args[3], @errorName(err) });
    };
    try out.flush();
}

fn Report(arena: std.mem.Allocator, io: std.Io, project_path: []const u8, engine_path: []const u8, game_name: []const u8, trees: bool, out: *std.Io.Writer) !void {
    const project_file = try std.fmt.allocPrint(arena, "{s}.imprj", .{game_name});
    const result = try ProjectWalk.WalkProject(arena, io, project_path, engine_path, project_file);
    const not_needed = try ProjectWalk.FindNotNeeded(arena, io, project_path, engine_path, &result);
    const checks = try ForestChecks.Run(arena, &result);
    if (trees) try ProjectWalk.WriteForest(out, &result);
    try ProjectWalk.WriteReport(out, game_name, &result, &not_needed);
    try ForestChecks.WriteChecks(out, &checks);
}
