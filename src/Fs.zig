const std = @import("std");

pub fn doesFileExist(fpath: []const u8) !bool {
    const file = (std.fs.cwd()).openFile(fpath, .{}) catch |e| switch (e) {
        error.FileNotFound => return false,
        error.IsDir => return true,
        else => return e,
    };
    defer file.close();
    return true;
}

pub fn openOrCreateLogFile(path: []const u8) !std.fs.File {
    var exists = try doesFileExist(path);
    var handle: std.fs.File = undefined;
    if (!exists) {
        var f = try std.fs.cwd().createFile(path, .{});
        f.close();
        handle = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    } else {
        handle = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    }
    return handle;
}
