const std = @import("std");
const zli = @import("./main.zig");
const RawTerm = zli.terminal.RawTerm;
const Mutex = std.Thread.Mutex;
const Color = zli.terminal.style.Color;

// zig fmt: off
pub const SpinnerVariants = enum(u8) { 
    Dotted, 
    DottedTwo,
    Bar,
    Bouncing,
    BouncingTwo,

    pub const SpinnerVariantValues = [@typeInfo(SpinnerVariants).Enum.fields.len][:0] const u8{
       "⣾⣽⣻⢿⡿⣟⣯⣷",
       "⠁⠂⠄⡀⢀⠠⠐⠈",
       "▉▊▋▌▍▎▏▎▍▌▋▊▉",

       "▖▖▘▘▝▝▗▗",
       "▌▌▀▀▐▐▄▄"
    };

    pub fn str(self: SpinnerVariants) [:0]const u8{
        return SpinnerVariantValues[@enumToInt(self)];
           
    }
    
};
// zig fmt: on
pub const SpinnerState = struct {
    isRunning: bool = false,
};

pub const SpinnerMode = enum { Progress, Indefinate };
/// A terminal spinner with optional progress.
pub const Spinner = struct {
    label: []const u8 = "Loading..",
    variant: SpinnerVariants = SpinnerVariants.Bar,
    state: SpinnerState = SpinnerState{},
    mode: SpinnerMode = SpinnerMode.Indefinate,
    progress: u64 = 0,
    lock: Mutex = Mutex{},
    color: Color = Color.Green,
    thread: std.Thread = undefined,

    /// Starts the spinner on a new thread. Caller does NOT need to join the created thread.
    pub fn start(self: *Spinner, out: anytype) !void {
        self.lock.lock();
        self.state.isRunning = true;

        self.lock.unlock();
        self.thread = try std.Thread.spawn(.{}, spin, .{ out, self });
        self.thread.detach();
    }

    /// Stops the spinner and resets it's progress.
    pub fn stop(self: *Spinner) !void {
        self.lock.lock();
        self.state.isRunning = false;
        self.lock.unlock();
        self.resetProgress();
    }
    pub fn setVariant(self: *Spinner, variant: SpinnerVariants) !void {
        self.lock.lock();
        self.variant = variant;
        self.lock.unlock();
    }

    /// Increments spinner progress by set amount.
    pub fn incrementProgress(self: *Spinner, amount: usize) !void {
        if (self.mode == SpinnerMode.Indefinate) return zli.errors.SpinnerError.WrongMode;
        self.lock.lock();
        self.progress += amount;
        self.lock.unlock();
    }

    /// Resets spinners progress to 0.
    pub fn resetProgress(self: *Spinner) void {
        self.lock.lock();
        self.progress = 0;
        self.lock.unlock();
    }
};

fn spin(out: anytype, self: *Spinner) !void {
    defer zli.terminal.clear.clearCurrentLine(out.writer()) catch {};
    var lastUpdate: u64 = undefined;
    while (true) {
        switch (self.state.isRunning) {
            false => return,
            else => {},
        }
        switch (self.mode) {
            .Indefinate => {},
            .Progress => {
                if (self.progress >= 100) {
                    self.state.isRunning = false;
                    return;
                }
            },
        }

        var code_point_iterator = (try std.unicode.Utf8View.init(self.variant.str())).iterator();
        try zli.terminal.cursor.hideCursor(out.writer());
        while (code_point_iterator.nextCodepoint()) |code_point| {
            if (lastUpdate == self.progress) {
                while (lastUpdate == self.progress) std.time.sleep(std.time.ns_per_s * 0.05);
            }
            try zli.terminal.clear.clearCurrentLine(out.writer());
            try zli.terminal.format.updateStyle(out.writer(), .{ .foreground = self.color }, .{});
            try out.writer().print("{u}", .{code_point});
            try zli.terminal.format.resetStyle(out.writer());
            if (self.mode == SpinnerMode.Progress) {
                try out.writer().print("{s} {any}%", .{ self.label, self.progress });
                lastUpdate = self.progress;
            }
            try zli.terminal.cursor.setCursorColumn(out.writer(), 0);
            std.time.sleep(std.time.ns_per_s * 0.05);
        }
    }
    self.state.isRunning = false;
    return;
}
