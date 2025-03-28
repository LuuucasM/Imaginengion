const std = @import("std");
const IM = @import("IM");

pub fn main() !void {
    var EngineAllocator = std.heap.DebugAllocator(.{}).init;
    const allocator = EngineAllocator.allocator();
    var application = IM.Application{};
    std.log.info("Initializing Application", .{});
    try application.Init(allocator);
    std.log.info("Running Application", .{});
    try application.Run();
    std.log.info("Deinitializing Application", .{});
    try application.Deinit();
    std.log.info("Exiting main", .{});
}
