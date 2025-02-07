# Zlog

A small, opinionated logger for Zig. Based on personal preferences,
this libray might not be useful for you, and that's OK!

## How to use

First include the module in your build.zig.zon, or run the following:
```bash
; zig fetch --save git+https://github.com/max-legrand/zlog
```
Then add the following to your build.zig:
```zig
const zlog_dep = b.dependency("zlog", .{
    .target = target,
    .optimize = optimize,
});
exe_mod.addImport("zlog", zlog_dep.module("zlog"));
```

## Example usage

Here are some small examples of how to use the library.

### Simple logging
```zig
const std = @import("std");
const logger = @import("zlog").Logger;

var log: logger = undefined;

pub fn main() !void {
    log = logger.init(.DEBUG, true, "main", null, null, std.heap.page_allocator) catch unreachable;
    defer log.deinit();
    log.info("Hello, World!", .{});
}
```
### Logging to a file
```zig
const std = @import("std");
const zlog = @import("zlog");

var log: zlog.Logger = undefined; // Declare log at the top level

fn setupLogger() !void {
    const cwd = std.fs.cwd();
    const log_file = try cwd.createFile("out.log", .{});

    // Initialize the logger with the file
    log = try zlog.Logger.init(
        zlog.Logger.Level.DEBUG,
        false,
        "main",
        log_file,
        log_file,
        std.heap.page_allocator,
    );
}

pub fn main() !void {
    try setupLogger();
    defer log.deinit();

    try inner_main();
    log.debug("Done!", .{});
}

fn inner_main() !void {
    try log.pushScope("inner_main"); //

    log.debug("Hello from inner_main!", .{});
    log.info("This is an info message.", .{});
    log.warn("A warning message.", .{});
    log.err("An error message.", .{});

    try log.popScope(); // Pop the scope
}
```
