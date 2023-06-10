const std = @import("std");
const zli = @import("./main.zig");
const json = std.json;
const time = std.time;
const log = std.log;
const ztime = zli.time;

pub fn openOrCreateLogFile(path: []const u8) !std.fs.File {
    var exists = try zli.fs.doesFileExist(path);
    var handle = blk: {
        if (!exists) {
            var f = try std.fs.cwd().createFile(path, .{});
            f.close();
            var handle = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
            break :blk handle;
        }

        break :blk try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    };
    return handle;
}
const builtin = @import("builtin");
const test_allocator = std.testing.allocator;

// Global logger setup
const log_conf = LogConfig.default();
const log_man = LogManager(log_conf);
const default_writer = std.io.getStdErr().writer();
const default_log_lvl = .debug;

pub var json_logger = log_man.Logger(@TypeOf(default_writer), .json, default_log_lvl)
    .new(default_writer) catch @panic("Failed to create global JSON logger");
pub var pretty_logger = log_man.Logger(@TypeOf(default_writer), .pretty, default_log_lvl)
    .new(default_writer) catch @panic("Failed to create global pretty logger");
pub var plain_logger = log_man.Logger(@TypeOf(default_writer), .plain, default_log_lvl)
    .new(default_writer) catch @panic("Failed to create global plain logger");

/// Term Colors
pub const TermColor = struct {
    pub const red = "\x1b[31m";
    pub const yellow = "\x1b[33m";
    pub const green = "\x1b[32m";
    pub const gray = "\x1b[90m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";
    pub const reset = "\x1b[0m";
};

/// Format for writing the time.
/// .unix_secs - example: 1680183
/// .test_mode - always 0
pub const TimeFormat = enum {
    unix_secs,
    test_mode,
};

/// Mode for log formats.
/// .pretty - good for console applications
/// .plain - pretty with no color
/// .json - good for log storage & querying
pub const FormatMode = enum {
    json,
    pretty,
    plain,
};

/// Log level.
/// Example: choosing .debug as the global log level will filter out .trace logs and show the rest
pub const LevelType = enum {
    off,
    panic,
    fatal,
    err,
    warn,
    info,
    debug,
    trace,
    /// Get log level in full text form
    pub fn asText(self: LevelType) []const u8 {
        return switch (self) {
            .off => "OFF",
            .panic => "PANIC",
            .fatal => "FATAL",
            .err => "ERR",
            .warn => "WARN",
            .info => "INFO",
            .debug => "DEBUG",
            .trace => "TRACE",
        };
    }
    /// Short string for pretty printing the log level
    fn as3Char(self: LevelType) []const u8 {
        return switch (self) {
            .off => "OFF",
            .panic => "PAN",
            .fatal => "FTL",
            .err => "ERR",
            .warn => "WRN",
            .info => "INF",
            .debug => "DBG",
            .trace => "TRC",
        };
    }
    /// The default log level is based on build mode.
    pub const default: LevelType = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .info,
        .ReleaseFast, .ReleaseSmall => .warn,
    };
};

/// Log Config type.
/// Passed into LogManager function.
pub const LogConfig = struct {
    min_log_lvl: LevelType,
    time_fmt: TimeFormat,
    buf_size: usize,

    const Self = @This();
    /// Default log config
    pub fn default() Self {
        return Self{
            .min_log_lvl = LevelType.default,
            .time_fmt = .unix_secs,
            .buf_size = 1000,
        };
    }
    /// Global log level is off, so nothing should be logged
    pub fn off() Self {
        return Self{
            .min_log_lvl = .off,
            .time_fmt = .unix_secs,
            .buf_size = 1000,
        };
    }
    /// Test mode where time values are all 0
    pub fn testMode() Self {
        return Self{
            .min_log_lvl = LevelType.default,
            .time_fmt = .test_mode,
            .buf_size = 1000,
        };
    }
};

/// Log Manager will take in a comptime LogConfig.
/// A program should need only one Log Manager which creates Loggers
pub fn LogManager(
    comptime conf: LogConfig,
) type {
    return struct {
        /// Get current time depending on the LogConfig's time_fmt.
        fn getTime() !ztime.DateTime {
            return switch (conf.time_fmt) {
                .unix_secs => ztime.DateTime.now(),
                .test_mode => {},
            };
        }

        /// Events write the logs.
        /// Add fields to the event, then send the log with send(), msg("foo"), or msgf("foo", .{}).
        pub fn Event(
            comptime WriterType: type,
            comptime fmt_mode: FormatMode,
            comptime log_lvl: LevelType,
        ) type {
            _ = fmt_mode;
            return struct {
                w: WriterType,
                buf: std.BoundedArray(u8, conf.buf_size),
                time_val: ztime.DateTime,

                const Self = @This();
                /// Creates new Event with current time
                fn new(writer: WriterType) !Self {
                    var newEvent = Self{
                        .w = writer,
                        .time_val = undefined,
                        .buf = undefined,
                    };
                    // Filter out lower log levels
                    comptime if (@enumToInt(log_lvl) > @enumToInt(conf.min_log_lvl) or (log_lvl == .off)) {
                        return newEvent;
                    };
                    const time_val = getTime();
                    newEvent.time_val = time_val;
                    newEvent.buf = try std.BoundedArray(u8, conf.buf_size).init(0);
                    const w = newEvent.buf.writer();

                    try w.print(TermColor.gray ++ "[{}/{}/{} {}:{}:{}] " ++ TermColor.reset, .{ time_val.years, time_val.months, time_val.days, time_val.hours, time_val.minutes, time_val.seconds });
                    const lvlStr = switch (log_lvl) {
                        .panic, .fatal, .err => TermColor.red,
                        .warn => TermColor.yellow,
                        .info => TermColor.blue,
                        .debug => TermColor.magenta,
                        .trace => TermColor.green,
                        else => "",
                    } ++ comptime log_lvl.as3Char() ++ TermColor.reset;
                    try w.writeAll(lvlStr);

                    return newEvent;
                }

                /// Add a key:value pair to this event
                /// no_quotes will remove the quotes around JSON in the case of a num/bool
                /// NOTE: must use msg, msgf, or send methods to dispatch log
                pub fn add(self: *Self, key: []const u8, comptime fmt_str: []const u8, comptime no_quotes: bool, args: anytype) !void {
                    _ = no_quotes;
                    // Filter out lower log levels
                    comptime if (@enumToInt(log_lvl) > @enumToInt(conf.min_log_lvl) or (log_lvl == .off)) {
                        return;
                    };
                    const w = self.buf.writer();

                    try w.print(TermColor.gray ++ " {s}=" ++ TermColor.reset, .{key});
                    try w.print(fmt_str, args);
                }
                /// Add key:str pair to ev.
                /// NOTE: must use msg, msgf, or send methods to dispatch log
                pub fn str(self: *Self, key: []const u8, val: []const u8) !void {
                    try self.add(key, "{s}", false, .{val});
                }
                /// Add key:str pair to event using format string with value struct.
                /// NOTE: must use msg, msgf, or send methods to dispatch log
                pub fn strf(self: *Self, key: []const u8, comptime fmt_str: []const u8, val: anytype) !void {
                    try self.add(key, fmt_str, false, val);
                }
                /// Add key:num pair to ev.
                /// NOTE: must use msg, msgf, or send methods to dispatch log
                pub fn num(self: *Self, key: []const u8, val: anytype) !void {
                    const valTinfo = @typeInfo(@TypeOf(val));
                    switch (comptime valTinfo) {
                        .Int, .Float, .ComptimeInt, .ComptimeFloat => try self.add(key, "{d}", true, .{val}),
                        else => @compileError("Expected int or float value, instead got " ++ @typeName(@TypeOf(val))),
                    }
                }
                /// Add key:boolean pair to event
                /// NOTE: must use msg, msgf, or send methods to dispatch log
                pub fn boolean(self: *Self, key: []const u8, val: anytype) !void {
                    const valTinfo = @typeInfo(@TypeOf(val));
                    switch (comptime valTinfo) {
                        .Bool => try self.add(key, "{d}", true, .{val}),
                        else => @compileError("Expected bool value, instead got " ++ @typeName(@TypeOf(val))),
                    }
                }
                /// Send this event to the writer with no message.
                /// The event should then be discarded.
                pub fn send(self: *Self) !void {
                    // Filter out lower log levels
                    comptime if (@enumToInt(log_lvl) > @enumToInt(conf.min_log_lvl) or (log_lvl == .off)) {
                        return;
                    };
                    try self.w.writeAll(self.buf.constSlice());
                    try self.w.writeAll("\n");
                }
                /// Send this event to the writer with the given message.
                /// The event should then be discarded.
                pub fn msg(self: *Self, msg_str: []const u8) !void {
                    try self.str("message", msg_str);
                    try self.send();
                }
                /// Send this event to the writer with a message from
                /// a format string and args struct.
                /// The event should then be discarded.
                pub fn msgf(self: *Self, comptime fmt_str: []const u8, args: anytype) !void {
                    try self.strf("message", fmt_str, args);
                    try self.send();
                }
            };
        }

        /// Loggers hold a context, and they create log Events to write logs
        pub fn Logger(
            comptime WriterType: type,
            comptime fmt_mode: FormatMode,
            comptime log_lvl: LevelType,
        ) type {
            return struct {
                w: WriterType,
                ctx: std.BoundedArray(u8, conf.buf_size),

                const Self = @This();
                /// Create new logger
                pub fn new(w: WriterType) !Self {
                    return Self{
                        .w = w,
                        .ctx = try std.BoundedArray(u8, conf.buf_size).init(0),
                    };
                }
                /// Return current logger log level
                pub fn getLevel() LevelType {
                    return log_lvl;
                }
                /// Returns a sublogger at the given log level
                pub fn sublogger(
                    self: *Self,
                    comptime lvl: LevelType,
                ) !Logger(WriterType, fmt_mode, lvl) {
                    var newCtx = try std.BoundedArray(u8, conf.buf_size).init(0);
                    try newCtx.writer().writeAll(self.ctx.constSlice());
                    return Logger(WriterType, fmt_mode, lvl){
                        .w = self.w,
                        .ctx = newCtx,
                    };
                }
                /// Add a key:value pair context to this logger
                /// no_quotes will remove the quotes around JSON in the case of a num/bool
                /// NOTE: must use msg, msgf, or send methods to dispatch log
                fn addCtx(self: *Self, key: []const u8, comptime fmt_str: []const u8, comptime no_quotes: bool, args: anytype) !void {
                    // Filter out lower log levels
                    comptime if (@enumToInt(log_lvl) > @enumToInt(conf.min_log_lvl) or (log_lvl == .off)) {
                        return;
                    };
                    const w = self.ctx.writer();
                    switch (fmt_mode) {
                        .json => {
                            try w.print(",\"{s}\":", .{key});
                            if (!no_quotes) {
                                try w.writeAll("\"");
                            }
                            try w.print(fmt_str, args);
                            if (!no_quotes) {
                                try w.writeAll("\"");
                            }
                        },
                        .plain => {
                            try w.print(" {s}=", .{key});
                            try w.print(fmt_str, args);
                        },
                        .pretty => {
                            try w.print(TermColor.gray ++ " {s}=" ++ TermColor.reset, .{key});
                            try w.print(fmt_str, args);
                        },
                    }
                }
                /// Add key:boolean context to this logger
                pub fn booleanCtx(self: *Self, key: []const u8, val: bool) !void {
                    try self.addCtx(key, "{}", true, .{val});
                }
                /// Add key:num context to this logger
                pub fn numCtx(self: *Self, key: []const u8, val: anytype) !void {
                    const valTinfo = @typeInfo(@TypeOf(val));
                    switch (comptime valTinfo) {
                        .Int, .Float, .ComptimeInt, .ComptimeFloat => try self.addCtx(key, "{d}", true, .{val}),
                        else => @compileError("Expected int or float value, instead got " ++ @typeName(@TypeOf(val))),
                    }
                }
                /// Add key:string context to this logger
                pub fn strCtx(self: *Self, key: []const u8, val: []const u8) !void {
                    try self.addCtx(key, "{s}", false, .{val});
                }
                /// Returns an event that at the given log level
                pub fn event(self: *Self, comptime lvl: LevelType) !Event(WriterType, fmt_mode, lvl) {
                    var newEvent = try Event(WriterType, fmt_mode, lvl).new(self.w);
                    try newEvent.buf.writer().writeAll(self.ctx.constSlice());
                    return newEvent;
                }
                /// Log a message at this logger's level
                pub fn print(self: *Self, msg: []const u8) !void {
                    // Filter out lower log levels
                    comptime if (@enumToInt(log_lvl) > @enumToInt(conf.min_log_lvl) or (log_lvl == .off)) {
                        return error.W;
                    };
                    var ev = try self.event(log_lvl);
                    try ev.msg(msg);
                }
            };
        }
    };
}

// --- TESTING ---
