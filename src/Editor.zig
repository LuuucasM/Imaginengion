const std = @import("std");
const IM = @import("IM");

pub fn main() !void {
    const zone = IM.Tracy.ZoneInit("Main", @src());
    defer zone.Deinit();
    var application = IM.Application{};
    std.log.info("Initializing Application", .{});
    try application.Init();
    std.log.info("Running Application", .{});
    try application.Run();
    std.log.info("Deinitializing Application", .{});
    try application.Deinit();
    std.log.info("Exiting main", .{});
}
