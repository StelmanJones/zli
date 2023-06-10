const std = @import("std");
const zli = @import("./main.zig");
const Color = zli.terminal.style.Color;
const Style = zli.terminal.style.Style;
const format = zli.terminal.format;
const time = std.time;
const testing = std.testing;
const Mutex = std.Thread.Mutex;
const Thread = std.Thread;
const ProgressBarError = zli.errors.ProgressBarError;
pub const ProgressBarStyle = struct {
    head: Color = Color.Green,
    filler: Color = Color.Green,
    empty: Color = Color{ .Grey = 40 },
};

const Variant = struct {
    head: []const u8,
    filler: []const u8,
    empty: []const u8,
};
pub const ProgressBarVariants = enum {
    Basic,
    Line,
    Bar,
    Cubes,

    pub fn characters(self: ProgressBarVariants) Variant {
        return switch (self) {
            .Basic => Variant{ .head = ">", .filler = "=", .empty = " " },
            .Line => Variant{ .head = "━", .empty = "━", .filler = "━" },
            .Bar => Variant{ .head = "█", .filler = "█", .empty = "▒" },
            .Cubes => Variant{ .head = "■", .filler = "■", .empty = "□" },
        };
    }
};

pub const ProgressBarConfig = struct { width: u32 = 40, max: u32 = 100, display_fraction: bool = false, display_percentage: bool = true };

/// A thread-safe progressbar with multiple styles.
pub const ProgressBar = struct {
    config: ProgressBarConfig = ProgressBarConfig{},
    is_running: bool = false,
    left_end: ?[]const u8 = " ",
    right_end: ?[]const u8 = " ",
    progress: u32 = 0,
    style: ProgressBarStyle = ProgressBarStyle{},
    filled: []const u8 = "━",
    head: []const u8 = "━",
    empty: []const u8 = "━",
    mutex: std.Thread.Mutex = std.Thread.Mutex{},
    thread: Thread = undefined,

    pub fn start(self: *ProgressBar, writer: anytype) !void {
        self.mutex.lock();
        if (self.max == 0) return ProgressBarError.InvalidMax;
        self.is_running = true;
        self.mutex.unlock();
        self.thread = try Thread.spawn(.{}, run, .{ self, writer });
        self.thread.detach();
    }

    pub fn stop(self: *ProgressBar) !void {
        self.mutex.lock();
        self.is_running = false;
        self.progress = 0;
        self.thread = undefined;
        self.mutex.unlock();
    }

    pub fn setVariant(self: *ProgressBar, variant: ProgressBarVariants) !void {
        if (self.is_running) return;
        var v = variant.characters();
        self.mutex.lock();
        self.filled = v.filler;
        self.head = v.head;
        self.empty = v.empty;
        self.mutex.unlock();
    }
    pub fn reset(self: *ProgressBar) !void {
        self.mutex.lock();
        self.progress = 0;
        self.mutex.unlock();
    }

    /// Draw the current state of the progress bar.
    /// Increase the progress by 1.
    /// Return the current progress, or `null` if complete.
    /// Re-renders the progress bar.
    pub fn next(self: *ProgressBar) !?u32 {
        self.mutex.lock();
        self.progress += 1;
        if (self.progress >= self.max) {
            self.mutex.unlock();
            try self.stop();
            return null;
        } else {
            var p = self.progress;
            self.mutex.unlock();
            return p;
        }
    }

    /// Increment the progress by `step`.
    /// Returns the current progress, or `null` if complete.
    /// Re-renders the progress bar.
    pub fn increment(self: *ProgressBar, step: u32) !void {
        self.mutex.lock();
        self.progress += step;
        if (self.progress == self.max) {
            self.mutex.unlock();
            try self.stop();
            return;
        }
        self.mutex.unlock();
    }
};

/// Initialize a new progress bar with a writer, typically stdout or stderr.
fn run(self: *ProgressBar, out: anytype) !void {
    var writer = out;
    try zli.terminal.cursor.hideCursor(writer);
    main: while (self.is_running) {
        const percent = @intToFloat(f32, self.progress) / @intToFloat(f32, self.config.max);
        const filled_width = @floatToInt(u32, percent * @intToFloat(f32, self.config.width));
        var remaining = self.config.width;

        try writer.writeByte('\r');
        try zli.terminal.clear.clearCurrentLine(writer);
        if (self.left_end) |char|
            _ = try writer.write(char);

        try format.updateStyle(writer, Style{ .foreground = self.style.filler }, .{});
        while (remaining > self.width - filled_width) : (remaining -= 1) {
            _ = try writer.write(self.filled);
        }
        try format.resetStyle(writer);

        try format.updateStyle(writer, Style{ .foreground = self.style.head }, .{});
        if (remaining > 0) {
            _ = try writer.write(self.head);
            remaining -= 1;
        }
        try format.resetStyle(writer);

        try format.updateStyle(writer, Style{ .foreground = self.style.empty }, .{});
        while (remaining > 0) : (remaining -= 1) {
            _ = try writer.write(self.empty);
        }
        try format.resetStyle(writer);
        if (self.right_end) |char| {
            _ = try writer.write(char);
        }

        if (self.config.display_fraction) {
            try writer.print(" {d}/{d}", .{ self.progress, self.config.max });
        }

        if (self.config.display_percentage) {
            if (percent == 0.0) {
                try writer.print(" 0%", .{});
            } else {
                try writer.print(" {d:.0}%", .{percent * 100});
            }
        }
        if (self.progress >= self.config.max) {
            self.is_running = false;
            try writer.writeByte('\r');
            try zli.terminal.cursor.showCursor(writer);
            break :main;
        }
        std.time.sleep(std.time.ns_per_s * 0.05);
    }
    zli.terminal.clear.clearCurrentLine(writer) catch {};
    try writer.writeByte('\r');
    try zli.terminal.cursor.showCursor(writer);
    return;
}
