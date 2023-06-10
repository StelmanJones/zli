const std = @import("std");
const mem = std.mem;
const zli = @import("./main.zig");
const term = zli.terminal;
const events = zli.events;
const cur = term.cursor;
const style = term.style;
const Style = style.Style;
const Color = style.Color;
const FontStyle = style.FontStyle;
/// Reads a line from reader and returns the result.
pub fn readLine(reader: anytype, alloc: mem.Allocator, max: u64) !?[]const u8 {
    var line: []const u8 = (try reader.readUntilDelimiterOrEofAlloc(alloc, '\n', max)) orelse return zli.errors.InputError.InvalidInput;
    // trim annoying windows-only carriage return character
    if (line.len == 0) return zli.errors.InputError.InvalidInput;
    if (@import("builtin").os.tag == .windows) {
        return std.mem.trimRight(u8, line, "\r");
    } else {
        return line;
    }
}

/// Prompts the user for information and returns value.
pub fn prompt(text: []const u8, reader: anytype, writer: anytype, allocator: mem.Allocator, max: u64) !?[]const u8 {
    _ = try writer.write(text);
    _ = try writer.write(" > ");
    var result = try readLine(reader, allocator, max);
    return result;
}
pub const ChainablePrompt = struct { id: []const u8, text: []const u8, max_length: usize = 512 };

/// Run multiple prompts. Caller must free memory.
pub fn promptChain(prompts: []const ChainablePrompt, reader: anytype, writer: anytype, alloc: std.mem.Allocator) !std.StringHashMap([]const u8) {
    const total = prompts.len;
    var vals = std.StringHashMap([]const u8).init(alloc);

    for (prompts, 0..) |p, i| {
        try term.format.updateStyle(writer, Style{ .foreground = Color.White, .font_style = FontStyle{ .bold = true, .dim = true } }, term.StandardStyles.default);
        try writer.print("[{d}/{d}] ", .{ i + 1, total });
        try term.format.resetStyle(writer);
        const result = try prompt(p.text, reader, writer, alloc, p.max_length);
        try vals.put(p.id, result.?);
        try term.clear.clearCurrentLine(writer);
    }

    return vals;
}
const boldStyle: Style = Style{ .font_style = FontStyle{ .bold = true } };
const defaultStyle: Style = Style{ .font_style = FontStyle{ .bold = false } };
const SelectionControls = "(arrow-up/k = up, arrow-down/j = down, ENTER = select)";

pub const Choice = struct { value: []const u8 };
pub const SelectPromptOptions = struct {
    choices: []const Choice,
    label: []const u8 = "Select:",
    cursor: []const u8 = "❯",
    cursor_style: Style = defaultStyle,
    label_style: Style = defaultStyle,
    choice_style: Style = defaultStyle,
    selected_style: Style = boldStyle,
};

pub fn selectPrompt(in: anytype, out: anytype, comptime opts: SelectPromptOptions) !?Choice {
    var writer = out.writer();
    comptime var cursor = " " ++ opts.cursor ++ " ";
    try cur.hideCursor(writer);

    var index_length: u64 = opts.choices.len - 1;
    var current_index: u64 = 0;

    outer: while (true) {
        try term.clear.clearScreen(writer);
        try setSelectedElement(out, cursor, opts, current_index);

        switch (try events.next(in)) {
            .key => |k| switch (k) {
                .char => |c| switch (c) {
                    'k' => {
                        if (current_index == 0) current_index = index_length else current_index = current_index - 1;
                    },
                    'j' => {
                        if (current_index == index_length) current_index = 0 else current_index += 1;
                    },
                    else => {},
                },

                .up => {
                    if (current_index == 0) current_index = index_length else current_index = current_index - 1;
                },
                .down => {
                    if (current_index == index_length) current_index = 0 else current_index += 1;
                },
                .enter => break :outer,
                else => {},
            },
            else => {},
        }
    }
    //try cur.setCursorColumn(writer, 0);
    try term.clear.clearScreen(writer);

    return opts.choices[current_index];
}
fn setSelectedElement(out: anytype, comptime cursor: []const u8, comptime opts: SelectPromptOptions, current_index: u64) !void {
    var padding = "\x20\x20\x20";
    var writer = out.writer();
    try term.clear.clearFromCursorToScreenEnd(writer);
    try writer.print("{s}\n", .{opts.label});
    try cur.setCursorColumn(writer, 0);

    for (opts.choices.len, 0..) |_, i| {
        // Bold with cursor and no new line.

        if (i == current_index) {
            try term.format.updateStyle(writer, opts.cursor_style, .{});
            try writer.print("{s}", .{cursor});
            try term.format.updateStyle(writer, opts.selected_style, opts.cursor_style);
            try writer.print("{s}\n", .{opts.choices[i].value});
            try term.format.resetStyle(writer);
            try cur.setCursorColumn(writer, 0);

            continue;
        } else {
            try writer.print("{s}", .{padding});
            try term.format.updateStyle(writer, opts.choice_style, .{});
            try writer.print("{s}\n", .{opts.choices[i].value});
            try term.format.resetStyle(writer);
            try cur.setCursorColumn(writer, 0);

            continue;
        }
    }
    try term.format.updateStyle(writer, Style{ .font_style = .{ .italic = true, .dim = true } }, .{});
    try writer.print("   {s}\n", .{SelectionControls});
    try term.format.resetStyle(writer);
    try cur.setCursorColumn(writer, 0);
}
test "prompt_tests" {
    const test_alloc = std.testing.allocator;
    const input_string: *const [12]u8 = "StelmanJones";
    var input_stream = std.io.fixedBufferStream(input_string);
    var result = try prompt("enter name: ", input_stream.reader(), std.io.getStdOut().writer(), test_alloc, 20);
    defer test_alloc.free(result.?);
    try std.testing.expectEqualStrings(@as([]const u8, input_string), result.?);
}

test "selection_test" {
    const input_string: *const [2]u8 = "j\r";
    var input_stream = std.io.fixedBufferStream(input_string);
    var buf: [20]u8 = undefined;
    const writer = std.io.fixedBufferStream(buf);
    const choices = &[_]Choice{ .{ .value = "NotJones" }, .{ .value = "StelmanJones" } };
    var result = try zli.input.selectPrompt(input_stream, writer, choices, "Test");
    try std.testing.expectEqualStrings(@as([]const u8, choices[1].value), result.?.value);
}
