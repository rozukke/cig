const stdpath = @import("std").fs.path;
const std = @import("std");
const mem = std.mem;

/// Return slice of path without the extension at the end
pub fn pathNoExt(path: []const u8) []const u8 {
    return path[0 .. path.len - stdpath.extension(path).len];
}

const arg_iter = @import("std").process.ArgIterator;

const Config = struct {
    file: []const u8 = undefined,
    lex: bool = false,
    parse: bool = false,
    codegen: bool = false,
    emit: bool = false,
};

pub fn processArgs() !Config {
    var config: Config = .{};
    var file: ?[]const u8 = null;

    var args = std.process.args();
    _ = args.skip();
    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "--lex")) {
            config.lex = true;
            continue;
        } else if (mem.eql(u8, arg, "--parse")) {
            config.parse = true;
            continue;
        } else if (mem.eql(u8, arg, "--codegen")) {
            config.codegen = true;
            continue;
        } else if (mem.eql(u8, arg, "-S")) {
            config.emit = true;
            continue;
        }

        if (file) |_| return error.TooManyArgs else file = arg;
    }

    if (file) |file_uw| {
        config.file = file_uw;
        return config;
    } else return error.FileNotProvided;
}
