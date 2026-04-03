const std = @import("std");
const testing = std.testing;
const zlog = @import("root.zig");

fn createLogFile(io: std.Io) std.Io.File {
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, "test_output.log", .{}) catch {
        return cwd.createFile(io, "test_output.log", .{}) catch unreachable;
    };

    cwd.deleteFile(io, "test_output.log") catch {};
    return cwd.createFile(io, "test_output.log", .{}) catch unreachable;
}

test "basic logging" {
    testing.log_level = .debug;
    const io = testing.io;
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer if (gpa.deinit() == .leak) {
        std.debug.print("Memory leaked", .{});
        std.process.exit(1);
    };

    // no colors, no initial scope, log to file
    const log_file = createLogFile(io);
    var log = try zlog.Logger.init(.INFO, false, null, log_file, log_file, allocator, io);
    defer log.deinit();

    log.debug("This should not appear", .{});
    log.info("This should appear", .{});
    log.warn("This should appear", .{});
    log.err("This should appear", .{});

    try log.pushScope("test");
    log.info("This should be printed with scope", .{});
    try log.popScope();

    const cwd = std.Io.Dir.cwd();
    const contents = try cwd.readFileAlloc(io, "test_output.log", allocator, .unlimited);
    defer allocator.free(contents);
    defer cwd.deleteFile(io, "test_output.log") catch {};

    // Assert there are only 4 logs printed
    var log_count: usize = 0;
    var it = std.mem.splitSequence(u8, contents, "\n");
    while (it.next()) |line| {
        if (std.mem.trim(u8, line, &[_]u8{ ' ', '\t', '\n' }).len == 0) continue;
        log_count += 1;
    }
    try testing.expectEqual(4, log_count);

    var last_log_line: ?[]const u8 = null;
    it = std.mem.splitSequence(u8, contents, "\n");
    while (it.next()) |line| {
        if (std.mem.trim(u8, line, &[_]u8{ ' ', '\t', '\n' }).len == 0) continue;
        last_log_line = line;
    }

    if (last_log_line) |line| {
        try testing.expectEqual(true, std.mem.containsAtLeast(u8, line, 1, "[INFO] (test) This should be printed with scope"));
    } else {
        try testing.expect(false);
    }
}
