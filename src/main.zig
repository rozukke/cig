const std = @import("std");
const util = @import("util.zig");
const mem = std.mem;
const fs = std.fs;
const Child = std.process.Child;

const EXIT_ERR = 1;
const EXIT_OK = 0;

pub const std_options = .{
    .logFn = log,
};

/// Custom log function for pretty formatting and colors
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // Formatting options
    const color, const lvl = switch (level) {
        // red
        .err => .{ "\x1b[31m", "ERR" },
        // yellow
        .warn => .{ "\x1b[33m", "WRN" },
        // blank
        .info => .{ "\x1b[0m", "INF" },
        // cyan
        .debug => .{ "\x1b[36m", "DBG" },
    };

    const prefix = color ++ "[" ++ lvl ++ "|" ++ @tagName(scope) ++ "] ";

    std.io.getStdErr().writer().print(prefix ++ format ++ "\n", args) catch {
        @panic("could not write log");
    };
}

/// Logger for compiler driver
const driver_log = std.log.scoped(.DRIVER);

pub fn main() !u8 {
    const args = std.os.argv;
    if (args.len < 2) {
        driver_log.err("Please provide a C file to compile", .{});
        return EXIT_ERR;
    }
    // Convert to []const u8
    const rel_path = mem.span(args[1]);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    _ = stdout;

    const cfile_noext = util.pathNoExt(rel_path);

    // Preprocess
    const preproc_file_name = try mem.concatWithSentinel(alloc, u8, &.{ cfile_noext, ".i" }, 0);
    defer alloc.free(preproc_file_name);

    driver_log.info("Calling preprocessor on file `{s}`", .{rel_path});
    const pre_proc = Child.run(.{
        .allocator = alloc,
        .argv = &.{
            "gcc",
            "-E",
            "-P",
            rel_path,
            "-o",
            preproc_file_name,
        },
    }) catch |err| {
        driver_log.err("Could not run preprocessor on file {s}: {s}", .{ rel_path, @errorName(err) });
        return EXIT_ERR;
    };
    defer alloc.free(pre_proc.stdout);
    defer alloc.free(pre_proc.stderr);

    if (pre_proc.term.Exited == 1) {
        driver_log.err("Command failed when preprocessing `{s}`:\n{s}", .{ rel_path, mem.trim(u8, pre_proc.stderr, "\n") });
        std.process.exit(1);
        return EXIT_ERR;
    }
    defer {
        driver_log.debug("Deleting file {s}", .{preproc_file_name});
        std.fs.cwd().deleteFile(preproc_file_name) catch {};
    }

    // Compile
    _ = "TODO: Next up is the lexer";

    // Assemble
    const asm_file_name = try mem.concatWithSentinel(alloc, u8, &.{ cfile_noext, ".s" }, 0);
    defer alloc.free(asm_file_name);

    driver_log.info("Calling assembler on file `{s}`", .{asm_file_name});
    const asm_proc = Child.run(.{ .allocator = alloc, .argv = &.{
        "gcc",
        asm_file_name,
        "-o",
        cfile_noext,
    } }) catch |err| {
        driver_log.err("Could not run assembler on file {s}: {s}", .{ rel_path, @errorName(err) });
        return EXIT_ERR;
    };
    defer alloc.free(asm_proc.stdout);
    defer alloc.free(asm_proc.stderr);

    if (asm_proc.term.Exited == 1) {
        driver_log.err("Could not assemble file `{s}`:\n{s}", .{ asm_file_name, mem.trim(u8, asm_proc.stderr, "\n") });
        return EXIT_ERR;
    }
    defer {
        driver_log.debug("Deleting file {s}", .{asm_file_name});
        std.fs.cwd().deleteFile(asm_file_name) catch {};
    }

    return EXIT_OK;
}
