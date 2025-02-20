const std = @import("std");
const unicode = std.unicode;

const Ast = union(enum) {};

/// Token with source info
const SourceToken = struct {
    tok: Token,
    span: Span,
};

const Span = struct {
    start: usize,
    end: usize,
};

/// Enum representing C keywords
const Token = enum {
    identifier,
    int_constant,
    kw_int,
    kw_return,
    kw_void,
    l_paren,
    r_paren,
    l_brace,
    r_brace,
    semicolon,
    invalid,
    eof,

    pub const keywords = std.StaticStringMap(Token).initComptime(.{
        .{ "int", .kw_int },
        .{ "return", .kw_return },
        .{ "void", .kw_void },
    });

    pub fn getKeyword(slice: []const u8) ?Token {
        return keywords.get(slice);
    }
};

// Kind of aped from the Zig tokenizer
pub const Tokenizer = struct {
    src: [:0]const u8,
    idx: usize,

    const State = enum {
        start,
        identifier,
        constant,
        invalid,
    };

    pub fn init(src: [:0]const u8) Tokenizer {
        // UTF-8 may start with byte order mark
        return .{
            .src = src,
            .idx = if (std.mem.startsWith(u8, src, "\xEF\xBB\xBF")) 3 else 0,
        };
    }

    inline fn curr(self: *Tokenizer) u8 {
        return self.src[self.idx];
    }

    pub fn next(self: *Tokenizer) SourceToken {
        var result: SourceToken = .{
            .tok = undefined,
            .span = .{
                .start = self.idx,
                .end = undefined,
            },
        };
        state: switch (State.start) {
            .start => switch (self.curr()) {
                0 => {
                    if (self.idx == self.src.len) {
                        return .{ .tok = .eof, .span = .{
                            .start = self.idx,
                            .end = self.idx,
                        } };
                    } else continue :state .invalid;
                },
                ' ', '\n', '\t', '\r' => {
                    self.idx += 1;
                    result.span.start = self.idx;
                    continue :state .start;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    result.tok = .identifier;
                    continue :state .identifier;
                },
                '0'...'9' => {
                    result.tok = .int_constant;
                    continue :state .constant;
                },
                '(' => {
                    result.tok = .l_paren;
                    self.idx += 1;
                },
                ')' => {
                    result.tok = .r_paren;
                    self.idx += 1;
                },
                '{' => {
                    result.tok = .l_brace;
                    self.idx += 1;
                },
                '}' => {
                    result.tok = .r_brace;
                    self.idx += 1;
                },
                ';' => {
                    result.tok = .semicolon;
                    self.idx += 1;
                },
                else => {
                    result.tok = .eof;
                },
            },
            .invalid => {
                self.idx += 1;
                // Continue invalid token until eof or newline
                switch (self.curr()) {
                    0 => if (self.idx == self.src.len) {
                        result.tok = .invalid;
                    } else {
                        continue :state .invalid;
                    },
                    '\n' => result.tok = .invalid,
                    else => continue :state .invalid,
                }
            },
            .identifier => {
                self.idx += 1;
                switch (self.curr()) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9' => {
                        continue :state .identifier;
                    },
                    else => {
                        const ident = self.src[result.span.start..self.idx];
                        if (Token.getKeyword(ident)) |tok| {
                            result.tok = tok;
                        }
                    },
                }
            },
            .constant => {
                self.idx += 1;
                switch (self.curr()) {
                    '0'...'9', '_' => {
                        continue :state .constant;
                    },
                    else => {},
                }
            },
        }

        result.span.end = self.idx;
        return result;
    }
};

fn assertTokenize(src: [:0]const u8, tokens: []const struct { Token, usize, usize }) !void {
    var tokenizer = Tokenizer.init(src);
    for (tokens) |expected| {
        const s_token = tokenizer.next();
        const exp_tok, const exp_start, const exp_end = expected;
        try std.testing.expectEqual(exp_tok, s_token.tok);
        try std.testing.expectEqual(exp_start, s_token.span.start);
        try std.testing.expectEqual(exp_end, s_token.span.end);
    }
    const last = tokenizer.next();
    try std.testing.expectEqual(Token.eof, last.tok);
    try std.testing.expectEqual(src.len, last.span.start);
    try std.testing.expectEqual(src.len, last.span.end);
}

test "tokenize parens" {
    try assertTokenize(" \n\t\r()", &.{ .{ .l_paren, 4, 5 }, .{ .r_paren, 5, 6 } });
}

test "tokenize braces" {
    try assertTokenize(" {\n\t\r}\n", &.{ .{ .l_brace, 1, 2 }, .{ .r_brace, 5, 6 } });
}

test "keywords" {
    try assertTokenize("int void return", &.{
        .{ .kw_int, 0, 3 },
        .{ .kw_void, 4, 8 },
        .{ .kw_return, 9, 15 },
    });
}

test "identifiers" {
    try assertTokenize("ints voids returns", &.{
        .{ .identifier, 0, 4 },
        .{ .identifier, 5, 10 },
        .{ .identifier, 11, 18 },
    });
}

test "bom" {
    try assertTokenize("\xEF\xBB\xBFint", &.{.{ .kw_int, 3, 6 }});
}

test "int constant" {
    try assertTokenize("1 33 3_000_000", &.{
        .{ .int_constant, 0, 1 },
        .{ .int_constant, 2, 4 },
        .{ .int_constant, 5, 14 },
    });
}

test "small program" {
    const program =
        \\int main(void) {
        \\    return 2;
        \\}
    ;
    try assertTokenize(program, &.{
        .{ .kw_int, 0, 3 },
        .{ .identifier, 4, 8 },
        .{ .l_paren, 8, 9 },
        .{ .kw_void, 9, 13 },
        .{ .r_paren, 13, 14 },
        .{ .l_brace, 15, 16 },
        .{ .kw_return, 21, 27 },
        .{ .int_constant, 28, 29 },
        .{ .semicolon, 29, 30 },
        .{ .r_brace, 31, 32 },
    });
}
