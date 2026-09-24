const std = @import("std");
const IM = @import("IM");

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
