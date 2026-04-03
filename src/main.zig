const std = @import("std");
const Logger = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;
    std.debug.print("Standard print...\n", .{});
    try Logger.initGlobalLogger(
        Logger.Logger.Level.DEBUG,
        true,
        "test",
        null,
        null,
        allocator,
        init.io,
    );
    defer Logger.deinitGlobalLogger();

    Logger.debug("Debug, world!", .{});
    Logger.info("Info, world!", .{});
    Logger.warn("Warn, world!", .{});
    Logger.err("Err, world!", .{});
}
