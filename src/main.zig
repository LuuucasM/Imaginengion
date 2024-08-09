const std = @import("std");
const Application = @import("Core/Application.zig");

pub fn main() !void {
    std.log.info("Initializing Application", .{});
    try Application.Init(std.heap.page_allocator);
    std.log.info("Running Application", .{});
    try Application.Run();
    std.log.info("Deinitializing Application", .{});
    Application.Deinit();
    std.log.info("Exiting main", .{});
}
