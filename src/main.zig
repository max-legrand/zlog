const std = @import("std");
const Logger = @import("root.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    try Logger.initGlobalLogger(
        Logger.Logger.Level.DEBUG,
        true,
        "test",
        null,
        null,
        allocator,
    );
    defer Logger.deinitGlobalLogger();

    Logger.debug("Debug, world!", .{});
    Logger.info("Info, world!", .{});
    Logger.warn("Warn, world!", .{});
    Logger.err("Err, world!", .{});
}
