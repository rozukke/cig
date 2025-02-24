const std = @import("std");

/// Logger for compiler driver
pub const driver_log = std.log.scoped(.DRIVER);
/// Logger for code emission
pub const emit_log = std.log.scoped(.EMIT);

/// Custom log function for pretty formatting and colors
pub fn prettyLog(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    // Formatting options
    const color, const lvl, const out = switch (level) {
        // red
        .err => .{ "\x1b[31m", "ERR", stderr },
        // yellow
        .warn => .{ "\x1b[33m", "WRN", stderr },
        // blank
        .info => .{ "", "INF", stdout },
        // cyan
        .debug => .{ "\x1b[36;2m", "DBG", stdout },
    };

    const prefix = color ++ "[" ++ lvl ++ "|" ++ @tagName(scope) ++ "] ";

    out.writer().print(prefix ++ format ++ "\n" ++ "\x1b[0m", args) catch {
        @panic("could not write log");
    };
}
