const std = @import("std");
const testing = std.testing;
pub const input = @import("./Input.zig");
pub const errors = @import("./Errors.zig");
pub const zigbench = @import("./zig-bench/bench.zig");
pub const fs = @import("./Fs.zig");
pub const parser = @import("./Cli.zig");
pub const logging = @import("./Logger.zig");
pub const terminal = @import("./Terminal.zig");
pub const events = @import("./Events.zig");
pub const time = @import("./Time.zig");
pub const spinner = @import("./Spinner.zig");
pub const progress = @import("./ProgressBar.zig");
pub const strings = @import("./Strings.zig");
pub const Theme = parser.Theme;
const Self = @This();
pub const ProgramOptions = struct { name: []const u8 = "ZLI", version: std.builtin.Version = .{ .major = 0, .minor = 1, .patch = 0 } };

pub const LibraryAllocator = std.testing.allocator;

// WARN: @StelmanJones Remove this struct.

test {
    @import("std").testing.refAllDecls(Self);
}
