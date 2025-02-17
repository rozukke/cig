const stdpath = @import("std").fs.path;

/// Return slice of path without the extension at the end
pub fn pathNoExt(path: []const u8) []const u8 {
    return path[0 .. path.len - stdpath.extension(path).len];
}
