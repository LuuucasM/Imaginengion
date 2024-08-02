const std = @import("std");
const Application = @import("Core/Application.zig");

pub fn main() !void {
    std.log.info("Initializing Application", .{});
    const app = try Application.Init(std.heap.page_allocator);
    std.log.info("Running Application", .{});
    app.Run();
    std.log.info("Deinitializing Application", .{});
    app.Deinit();
    std.log.info("Exiting main", .{});
}
