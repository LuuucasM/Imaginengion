const std = @import("std");
const Application = @import("Core/Application.zig");

pub fn main() !void {
    std.log.info("Initializing Application", .{});
    var application = Application{};
    try application.Init();
    std.log.info("Running Application", .{});
    try application.Run();
    std.log.info("Deinitializing Application", .{});
    try application.Deinit();
    std.log.info("Exiting main", .{});
}
