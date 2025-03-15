const std = @import("std");
const c = @cImport({
    @cInclude("time.h");
});

const heap_allocator = std.heap.page_allocator;

var stdout_mutex = std.Thread.Mutex.Recursive.init;
var stderr_mutex = std.Thread.Mutex.Recursive.init;
fn lockStdout() void {
    stdout_mutex.lock();
}
fn unlockStdout() void {
    stdout_mutex.unlock();
}
fn lockStderr() void {
    stderr_mutex.lock();
}
fn unlockStderr() void {
    stderr_mutex.unlock();
}

pub const Logger = struct {
    pub const Level = enum {
        DEBUG,
        INFO,
        WARN,
        ERROR,

        pub fn toString(self: Level) []const u8 {
            return switch (self) {
                .DEBUG => "DEBUG",
                .INFO => "INFO",
                .WARN => "WARN",
                .ERROR => "ERROR",
            };
        }

        pub fn getColor(self: Level) []const u8 {
            return switch (self) {
                .DEBUG => "\x1b[35m", // Purple
                .INFO => "\x1b[36m", // Cyan
                .WARN => "\x1b[33m", // Yellow
                .ERROR => "\x1b[31m", // Red
            };
        }
    };

    level: Level,
    scope_stack: std.ArrayList([]const u8),
    stdout: ?std.fs.File,
    stderr: ?std.fs.File,
    colors: bool,
    allocator: std.mem.Allocator,
    scope_mutex: std.Thread.Mutex.Recursive,

    pub fn init(
        level: Level,
        colors: bool,
        scope: ?[]const u8,
        stdout: ?std.fs.File,
        stderr: ?std.fs.File,
        arg_allocator: ?std.mem.Allocator,
    ) !Logger {
        const allocator = if (arg_allocator) |a| a else heap_allocator;
        var scope_stack = std.ArrayList([]const u8).init(allocator);
        if (scope) |s| try scope_stack.append(s);
        return .{
            .level = level,
            .scope_stack = scope_stack,
            .stdout = stdout,
            .stderr = stderr,
            .colors = colors,
            .allocator = allocator,
            .scope_mutex = std.Thread.Mutex.Recursive.init,
        };
    }

    pub fn pushScope(self: *Logger, scope: []const u8) !void {
        self.scope_mutex.lock();
        defer self.scope_mutex.unlock();

        try self.scope_stack.append(scope);
    }

    pub fn popScope(self: *Logger) !void {
        self.scope_mutex.lock();
        defer self.scope_mutex.unlock();

        if (self.scope_stack.items.len > 0) {
            _ = self.scope_stack.pop();
        }
    }

    fn getCurrentScope(self: *Logger) []const u8 {
        self.scope_mutex.lock();
        defer self.scope_mutex.unlock();

        if (self.scope_stack.items.len > 0) {
            return self.scope_stack.items[self.scope_stack.items.len - 1];
        } else {
            return "";
        }
    }

    fn log(self: *Logger, level: Level, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(level) < @intFromEnum(self.level)) return;

        const is_error = level == .ERROR;
        const writer = if (level == .ERROR)
            if (self.stderr) |err_file| err_file.writer() else std.io.getStdErr().writer()
        else if (self.stdout) |out_file| out_file.writer() else std.io.getStdOut().writer();

        // Get current time
        const timestamp = std.time.timestamp();
        var time_struct: c.tm = undefined;
        const time_ptr = c.localtime(&timestamp);
        if (time_ptr) |tm| {
            time_struct = tm.*;
        } else return;

        // Format the time string
        var time_buf: [32]u8 = undefined;
        _ = c.strftime(&time_buf, time_buf.len, "%Y-%m-%d %H:%M:%S", &time_struct);

        // Build the log message in a buffer first
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();

        const bufWriter = buf.writer();

        if (self.colors) {
            bufWriter.print("{s}", .{level.getColor()}) catch return;
        }

        const current_scope = self.getCurrentScope();
        if (std.mem.eql(u8, current_scope, "")) {
            bufWriter.print("{s} [{s}] ", .{
                std.mem.sliceTo(&time_buf, 0),
                level.toString(),
            }) catch return;
        } else {
            bufWriter.print("{s} [{s}] ({s}) ", .{
                std.mem.sliceTo(&time_buf, 0),
                level.toString(),
                current_scope,
            }) catch return;
        }

        if (self.colors) {
            bufWriter.print("\x1b[0m", .{}) catch return; // Reset color
        }

        bufWriter.print(fmt ++ "\n", args) catch return;

        if (is_error) {
            if (self.stderr != null) {
                // Custom file, no need for the global lock
            } else {
                lockStderr();
                defer unlockStderr();
            }
        } else {
            if (self.stdout != null) {
                // Custom file, no need for the global lock
            } else {
                lockStdout();
                defer unlockStdout();
            }
        }

        // Write the entire message at once
        nosuspend writer.writeAll(buf.items) catch {};
    }

    pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.DEBUG, fmt, args);
    }

    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.INFO, fmt, args);
    }

    pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.WARN, fmt, args);
    }

    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.ERROR, fmt, args);
    }

    pub fn deinit(self: *Logger) void {
        self.scope_mutex.lock();
        defer self.scope_mutex.unlock();

        var same_file = false;
        if (self.stdout != null and self.stderr != null) {
            const stdout = self.stdout.?;
            const stderr = self.stderr.?;
            if (stdout.handle == stderr.handle) {
                same_file = true;
            }
        }
        if (self.stdout) |file| {
            std.fs.File.close(file);
        }
        if (self.stderr) |file| {
            if (!same_file) {
                std.fs.File.close(file);
            }
        }
        self.scope_stack.deinit();
    }
};

// Global logging instance
pub var glog: Logger = undefined;

pub fn initGlobalLogger(
    level: Logger.Level,
    colors: bool,
    scope: ?[]const u8,
    stdout: ?std.fs.File,
    stderr: ?std.fs.File,
    allocator: ?std.mem.Allocator,
) !void {
    glog = try Logger.init(level, colors, scope, stdout, stderr, allocator);
}

pub fn deinitGlobalLogger() void {
    glog.deinit();
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    glog.debug(fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    glog.info(fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    glog.warn(fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    glog.err(fmt, args);
}

pub fn setLevel(level: Logger.Level) void {
    glog.level = level;
}

pub fn pushScope(scope: []const u8) !void {
    try glog.pushScope(scope);
}

pub fn popScope() ![]const u8 {
    glog.scope_mutex.lock();
    defer glog.scope_mutex.unlock();

    if (glog.scope_stack.items.len > 0) {
        const prev = glog.scope_stack.pop();
        if (prev) |p| return p;
        return "";
    }
    return "";
}
