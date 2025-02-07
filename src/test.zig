const std = @import("std");
const testing = std.testing;
const zlog = @import("root.zig");

fn createLogFile() std.fs.File {
    const cwd = std.fs.cwd();
    cwd.access("test_output.log", .{}) catch {
        return cwd.createFile("test_output.log", .{}) catch unreachable;
    };

    cwd.deleteFile("test_output.log") catch {};
    return cwd.createFile("test_output.log", .{}) catch unreachable;
}

test "basic logging" {
    testing.log_level = .debug;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() == .leak) {
        std.debug.print("Memory leaked", .{});
        std.process.exit(1);
    };

    // no colors, no initial scope, log to file
    const log_file = createLogFile();
    var log = try zlog.Logger.init(.INFO, false, null, log_file, log_file, allocator);
    defer log.deinit();

    log.debug("This should not appear", .{});
    log.info("This should appear", .{});
    log.warn("This should appear", .{});
    log.err("This should appear", .{});

    try log.pushScope("test");
    defer log.popScope() catch error.ScopeStackEmpty;
    log.info("This should be printed with scope", .{});

    const cwd = std.fs.cwd();
    const contents = try cwd.readFileAlloc(allocator, "test_output.log", std.math.maxInt(usize));
    defer allocator.free(contents);
    // defer cwd.deleteFile("test_output.log") catch {};

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
