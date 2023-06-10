const std = @import("std");

/// Ansi Formatting module.
pub const format = @import("./terminal/format.zig");
/// Cursor manipulation module.
pub const cursor = @import("./terminal/cursor.zig");
/// Terminal Clearing module.
pub const clear = @import("./terminal/clear.zig");
/// Style module.
pub const style = @import("./terminal/style.zig");

/// TTY Stuff.
pub usingnamespace @import("./terminal/terminal.zig");

const Style = style.Style;
const FontStyle = style.FontStyle;
const Color = style.Color;

/// Some Standard Ansi Styles.
pub const StandardStyles = struct {
    pub const success = Style{
        .foreground = Color.Green,
        .font_style = FontStyle.bold,
    };
    pub const warn = Style{
        .foreground = Color.Yellow,
        .font_style = FontStyle.bold,
    };
    pub const err = Style{
        .foreground = Color.Red,
        .font_style = FontStyle.bold,
    };
    pub const default = Style{
        .foreground = Color.White,
    };
    pub const dimmed = Style{ .foreground = Color{ .Grey = 40 } };
};
