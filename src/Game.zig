const std = @import("std");
const IM = @import("IM");

/// What the engine runs, see Programs/Program.zig
pub const Program = IM.GameProgram;

pub fn main(init: std.process.Init.Minimal) !void {
    var application = IM.Application{};
    std.log.info("Initializing Application", .{});
    try application.Init(init);
    std.log.info("Running Application", .{});
    try application.Run();
    std.log.info("Deinitializing Application", .{});
    application.Deinit();
    std.log.info("Exiting main", .{});
}
