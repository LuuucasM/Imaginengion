const std = @import("std");
const Application = @import("Core/Application.zig");

pub fn main() !void {
    std.log.info("Initializing Application", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    try Application.Init(gpa.allocator());
    std.log.info("Running Application", .{});
    try Application.Run();
    std.log.info("Deinitializing Application", .{});
    try Application.Deinit();
    std.log.info("Exiting main", .{});
}
