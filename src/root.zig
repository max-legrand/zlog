const std = @import("std");
const c = @import("c");

var stdout_mutex = std.Io.Mutex.init;
var stderr_mutex = std.Io.Mutex.init;
fn lockStdout(io: std.Io) !void {
    try stdout_mutex.lock(io);
}
fn unlockStdout(io: std.Io) void {
    stdout_mutex.unlock(io);
}
fn lockStderr(io: std.Io) !void {
    try stderr_mutex.lock(io);
}
fn unlockStderr(io: std.Io) void {
    stderr_mutex.unlock(io);
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
    stdout: ?std.Io.File,
    stderr: ?std.Io.File,
    colors: bool,
    allocator: std.mem.Allocator,
    scope_mutex: std.Io.Mutex,
    io: std.Io,

    pub fn init(
        level: Level,
        colors: bool,
        scope: ?[]const u8,
        stdout: ?std.Io.File,
        stderr: ?std.Io.File,
        allocator: std.mem.Allocator,
        io: std.Io,
    ) !Logger {
        var scope_stack = std.ArrayList([]const u8).empty;
        if (scope) |s| try scope_stack.append(allocator, s);
        return .{
            .level = level,
            .scope_stack = scope_stack,
            .stdout = stdout,
            .stderr = stderr,
            .colors = colors,
            .allocator = allocator,
            .scope_mutex = std.Io.Mutex.init,
            .io = io,
        };
    }

    pub fn pushScope(self: *Logger, scope: []const u8) !void {
        try self.scope_mutex.lock(self.io);
        defer self.scope_mutex.unlock(self.io);

        try self.scope_stack.append(self.allocator, scope);
    }

    pub fn popScope(self: *Logger) !void {
        try self.scope_mutex.lock(self.io);
        defer self.scope_mutex.unlock(self.io);

        if (self.scope_stack.items.len > 0) {
            _ = self.scope_stack.pop();
        }
    }

    fn getCurrentScope(self: *Logger) ![]const u8 {
        try self.scope_mutex.lock(self.io);
        defer self.scope_mutex.unlock(self.io);

        if (self.scope_stack.items.len > 0) {
            return self.scope_stack.items[self.scope_stack.items.len - 1];
        } else {
            return "";
        }
    }

    fn log(self: *Logger, level: Level, comptime fmt: []const u8, args: anytype) !void {
        if (@backingInt(level) < @backingInt(self.level)) return;

        const is_error = level == .ERROR;

        // Get current time
        const clock = std.Io.Clock.real;
        const current_time: i64 = clock.now(self.io).toMilliseconds();
        const timestamp = @divFloor(current_time, 1000);
        const ms: u32 = @intCast(@mod(current_time, 1000));

        var time_struct: c.tm = undefined;
        const time_ptr = c.localtime(&timestamp);
        if (time_ptr) |tm| {
            time_struct = tm.*;
        } else return;

        // Format the time string
        var time_buf: [32]u8 = undefined;
        _ = c.strftime(&time_buf, time_buf.len, "%Y-%m-%d %H:%M:%S", &time_struct);

        // Build the log message in a buffer first
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(self.allocator);

        if (self.colors) {
            buf.print(self.allocator, "{s}", .{level.getColor()}) catch return;
        }

        const current_scope = try self.getCurrentScope();
        if (std.mem.eql(u8, current_scope, "")) {
            buf.print(self.allocator, "{s}.{:0>3} [{s}] ", .{
                std.mem.sliceTo(&time_buf, 0),
                ms,
                level.toString(),
            }) catch return;
        } else {
            buf.print(self.allocator, "{s}.{:0>3} [{s}] ({s}) ", .{
                std.mem.sliceTo(&time_buf, 0),
                ms,
                level.toString(),
                current_scope,
            }) catch return;
        }

        if (self.colors) {
            buf.print(self.allocator, "\x1b[0m", .{}) catch return; // Reset color
        }

        buf.print(self.allocator, fmt ++ "\n", args) catch return;

        var stderr_locked = false;
        var stdout_locked = false;
        if (is_error) {
            if (self.stderr != null) {
                // Custom file, no need for the global lock
            } else {
                try lockStderr(self.io);
                stderr_locked = true;
            }
        } else {
            if (self.stdout != null) {
                // Custom file, no need for the global lock
            } else {
                try lockStdout(self.io);
                stdout_locked = true;
            }
        }

        var buffer: [1024]u8 = undefined;
        if (level == .ERROR) {
            if (self.stderr) |err_file| {
                var file_writer = err_file.writerStreaming(self.io, &buffer);
                var writer = &file_writer.interface;
                writer.writeAll(buf.items) catch return;
                writer.flush() catch return;
            } else {
                const stderr = std.Io.File.stderr();
                var file_writer = stderr.writerStreaming(self.io, &buffer);
                var writer = &file_writer.interface;
                writer.writeAll(buf.items) catch return;
                writer.flush() catch return;
            }
        } else {
            if (self.stdout) |out_file| {
                var file_writer = out_file.writerStreaming(self.io, &buffer);
                var writer = &file_writer.interface;
                writer.writeAll(buf.items) catch return;
                writer.flush() catch return;
            } else {
                const stdout = std.Io.File.stdout();
                var file_writer = stdout.writerStreaming(self.io, &buffer);
                var writer = &file_writer.interface;
                writer.writeAll(buf.items) catch return;
                writer.flush() catch return;
            }
        }
        if (stderr_locked) unlockStderr(self.io);
        if (stdout_locked) unlockStdout(self.io);
    }

    pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.DEBUG, fmt, args) catch {};
    }

    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.INFO, fmt, args) catch {};
    }

    pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.WARN, fmt, args) catch {};
    }

    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.ERROR, fmt, args) catch {};
    }

    pub fn deinit(self: *Logger) void {
        self.scope_mutex.lock(self.io) catch @panic("Failed to acquire mutex lock");
        defer self.scope_mutex.unlock(self.io);

        var same_file = false;
        if (self.stdout != null and self.stderr != null) {
            const stdout = self.stdout.?;
            const stderr = self.stderr.?;
            if (stdout.handle == stderr.handle) {
                same_file = true;
            }
        }
        if (self.stdout) |file| {
            file.close(self.io);
        }
        if (self.stderr) |file| {
            if (!same_file) {
                file.close(self.io);
            }
        }
        self.scope_stack.deinit(self.allocator);
    }
};

// Global logging instance
pub var glog: Logger = undefined;
var glog_set = false;

pub fn initGlobalLogger(
    level: Logger.Level,
    colors: bool,
    scope: ?[]const u8,
    stdout: ?std.Io.File,
    stderr: ?std.Io.File,
    allocator: std.mem.Allocator,
    io: std.Io,
) !void {
    glog = try Logger.init(level, colors, scope, stdout, stderr, allocator, io);
    glog_set = true;
}

/// Opinionated default global logger
pub fn initGlogDefault(allocator: std.mem.Allocator, io: std.Io) !void {
    glog = try Logger.init(
        .INFO,
        true,
        null,
        null,
        null,
        allocator,
        io,
    );
    glog_set = true;
}

pub fn printStack() void {
    if (!glog_set) {
        @panic("Global logger not initialized");
    }
    for (glog.scope_stack.items) |scope| {
        std.debug.print("{s}\n", .{scope});
    }
}

pub fn deinitGlobalLogger() void {
    if (!glog_set) {
        @panic("Global logger not initialized");
    }
    glog.deinit();
    glog_set = false;
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (!glog_set) {
        @panic("Global logger not initialized");
    }
    glog.debug(fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (!glog_set) {
        @panic("Global logger not initialized");
    }
    glog.info(fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (!glog_set) {
        @panic("Global logger not initialized");
    }
    glog.warn(fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (!glog_set) {
        @panic("Global logger not initialized");
    }
    glog.err(fmt, args);
}

pub fn setLevel(level: Logger.Level) void {
    if (!glog_set) {
        @panic("Global logger not initialized");
    }
    glog.level = level;
}

pub fn pushScope(scope: []const u8) !void {
    if (!glog_set) {
        @panic("Global logger not initialized");
    }
    try glog.pushScope(scope);
}

pub fn popScope() ![]const u8 {
    if (!glog_set) {
        @panic("Global logger not initialized");
    }
    glog.scope_mutex.lock(glog.io) catch @panic("Failed to acquire mutex lock");
    defer glog.scope_mutex.unlock(glog.io);

    if (glog.scope_stack.items.len > 0) {
        const prev = glog.scope_stack.pop();
        if (prev) |p| return p;
        return "";
    }
    return "";
}
