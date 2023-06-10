const std = @import("std");
const terminal = @import("../main.zig").terminal;
const Style = terminal.style.Style;
const StandardStyles = terminal.StandardStyles;

pub const Theme = struct { param_name_style: Style = StandardStyles.default, param_value_style: Style = StandardStyles.default, description_style: Style = StandardStyles.default, program_name_style: Style = StandardStyles.default, program_version_style: Style = StandardStyles.default };
