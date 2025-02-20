const std = @import("std");
const util = @import("util.zig");
const mem = std.mem;
const fs = std.fs;
const Child = std.process.Child;

const lex = @import("lex.zig");
const ast = @import("ast.zig");

const EXIT_ERR = 1;
const EXIT_OK = 0;

pub const std_options = std.Options{
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
        .info => .{ "", "INF" },
        // cyan
        .debug => .{ "\x1b[36;2m", "DBG" },
    };

    const prefix = color ++ "[" ++ lvl ++ "|" ++ @tagName(scope) ++ "] ";

    std.io.getStdErr().writer().print(prefix ++ format ++ "\n" ++ "\x1b[0m", args) catch {
        @panic("could not write log");
    };
}

/// Logger for compiler driver
const driver_log = std.log.scoped(.DRIVER);

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const config = util.processArgs() catch |err| {
        driver_log.err("Args error: {s}", .{@errorName(err)});
        return EXIT_ERR;
    };
    const rel_path = config.file;

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    _ = stdout;

    const cfile_noext = util.pathNoExt(rel_path);

    // Preprocess
    const preproc_file_path = try mem.concatWithSentinel(alloc, u8, &.{ cfile_noext, ".i" }, 0);
    defer alloc.free(preproc_file_path);

    driver_log.info("Calling preprocessor on `{s}`", .{rel_path});
    const pre_proc = Child.run(.{
        .allocator = alloc,
        .argv = &.{
            "gcc",
            "-E",
            "-P",
            rel_path,
            "-o",
            preproc_file_path,
        },
    }) catch |err| {
        driver_log.err("Could not run preprocessor on `{s}`: {s}", .{ rel_path, @errorName(err) });
        return EXIT_ERR;
    };
    defer alloc.free(pre_proc.stdout);
    defer alloc.free(pre_proc.stderr);

    if (pre_proc.term.Exited == 1) {
        driver_log.err("Command failed when preprocessing `{s}`\n{s}", .{ rel_path, mem.trim(u8, pre_proc.stderr, "\n") });
        std.process.exit(1);
        return EXIT_ERR;
    }
    defer {
        driver_log.debug("Deleting `{s}`", .{preproc_file_path});
        std.fs.cwd().deleteFile(preproc_file_path) catch {};
    }

    // Read preprocessed file
    const cwd = std.fs.cwd();
    // Supports 10MB files I suppose?
    const src = try cwd.readFileAllocOptions(alloc, preproc_file_path, 10_000_000, null, 1, 0);
    defer alloc.free(src);

    // Lexing
    var tokenizer = lex.Tokenizer.init(src);
    if (config.lex) {
        while (true) {
            const tok = tokenizer.next();
            switch (tok.tok) {
                .invalid => {
                    return EXIT_ERR;
                },
                .eof => {
                    break;
                },
                else => {},
            }
        }
        driver_log.warn("Stopping at lexing phase", .{});
        return EXIT_OK;
    }
    var parser = ast.Parser.init(&tokenizer);
    const ast_res = parser.tryParse() catch return EXIT_ERR;
    _ = ast_res;
    if (config.parse) {
        driver_log.warn("Stopping at parsing phase", .{});
        return EXIT_OK;
    }
    if (config.codegen) {
        driver_log.warn("Stopping at codegen phase", .{});
        return EXIT_OK;
    }
    if (config.emit) {
        driver_log.warn("Stopping at emission phase", .{});
        return EXIT_OK;
    }

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
        driver_log.err("Could not run assembler on `{s}`: {s}", .{ rel_path, @errorName(err) });
        return EXIT_ERR;
    };
    defer alloc.free(asm_proc.stdout);
    defer alloc.free(asm_proc.stderr);

    if (asm_proc.term.Exited == 1) {
        driver_log.err("Could not assemble file `{s}`\n{s}", .{ asm_file_name, mem.trim(u8, asm_proc.stderr, "\n") });
        return EXIT_ERR;
    }
    defer {
        driver_log.debug("Deleting `{s}`", .{asm_file_name});
        std.fs.cwd().deleteFile(asm_file_name) catch {};
    }

    return EXIT_OK;
}

test "Test runner" {
    std.testing.refAllDecls(@This());
}
