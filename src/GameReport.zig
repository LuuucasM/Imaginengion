//! What `zig build game` runs after building a game: prints which of its files it needs (GameBuild/ProjectWalk.zig). It only
//! reports, so whatever goes wrong here is printed and the build carries on.
//! GameReport <project folder> <engine folder> <game name>, the project file being <game name>.imprj
const std = @import("std");
const ProjectWalk = @import("Imaginengion/GameBuild/ProjectWalk.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &stdout.interface;

    Report(arena, init.io, args[1], args[2], args[3], out) catch |err| {
        try out.print("Couldn't work out which files {s} needs: {s}\n", .{ args[3], @errorName(err) });
    };
    try out.flush();
}

fn Report(arena: std.mem.Allocator, io: std.Io, project_path: []const u8, engine_path: []const u8, game_name: []const u8, out: *std.Io.Writer) !void {
    const project_file = try std.fmt.allocPrint(arena, "{s}.imprj", .{game_name});
    const result = try ProjectWalk.WalkProject(arena, io, project_path, engine_path, project_file);
    const not_needed = try ProjectWalk.FindNotNeeded(arena, io, project_path, engine_path, &result);
    try ProjectWalk.WriteReport(out, game_name, &result, &not_needed);
}
