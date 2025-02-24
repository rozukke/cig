const std = @import("std");

/// Token with source info
pub const SourceToken = struct {
    tok: Token,
    span: Span,
};

const Span = struct {
    start: usize,
    end: usize,

    pub fn toSrcSlice(self: Span, src: []const u8) []const u8 {
        return src[self.start..self.end];
    }
};

/// Enum representing C keywords
pub const Token = enum {
    identifier,
    int_constant,
    kw_int,
    kw_return,
    kw_void,
    l_paren,
    r_paren,
    l_brace,
    r_brace,
    tilde,
    minus,
    decrement,
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
        minus,
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

    inline fn bump(self: *Tokenizer) u8 {
        self.idx += 1;
        return self.curr();
    }

    inline fn peek(self: *Tokenizer) u8 {
        return self.src[self.idx + 1];
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
                '-' => {
                    result.tok = .minus;
                    continue :state .minus;
                },
                '~' => {
                    result.tok = .tilde;
                    self.idx += 1;
                },
                ';' => {
                    result.tok = .semicolon;
                    self.idx += 1;
                },
                else => {
                    continue :state .invalid;
                },
            },
            .invalid => {
                // Continue invalid token until eof or newline
                switch (self.bump()) {
                    0 => if (self.idx == self.src.len) {
                        result.tok = .invalid;
                    } else {
                        continue :state .invalid;
                    },
                    ' ', '\n', '\t', '\r' => result.tok = .invalid,
                    else => continue :state .invalid,
                }
            },
            .identifier => {
                switch (self.bump()) {
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
                switch (self.bump()) {
                    '0'...'9' => {
                        continue :state .constant;
                    },
                    '_', 'a'...'z', 'A'...'Z' => {
                        continue :state .invalid;
                    },
                    else => {},
                }
            },
            .minus => {
                switch (self.bump()) {
                    '-' => {
                        continue :state .invalid;
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
    try assertTokenize("_int void9 r3turn_", &.{
        .{ .identifier, 0, 4 },
        .{ .identifier, 5, 10 },
        .{ .identifier, 11, 18 },
    });
}

test "bom" {
    try assertTokenize("\xEF\xBB\xBFints", &.{.{ .identifier, 3, 7 }});
}

test "int constant" {
    try assertTokenize("1 23 3456789 123_ 4e5", &.{
        .{ .int_constant, 0, 1 },
        .{ .int_constant, 2, 4 },
        .{ .int_constant, 5, 12 },
        .{ .invalid, 13, 17 },
        .{ .invalid, 18, 21 },
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
