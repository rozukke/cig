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
    int,
    return_kw,
    void,
    l_paren,
    r_paren,
    l_brace,
    r_brace,
    semi,
    eof,
};

// Kind of aped from the Zig tokenizer
pub const Tokenizer = struct {
    src: [:0]const u8,
    idx: usize,

    const State = enum {
        start,
        identifier,
        invalid,
    };

    pub fn init(src: [:0]const u8) Tokenizer {
        // UTF-8 may start with byte order mark
        return .{
            .src = src,
            .idx = if (std.mem.startsWith(u8, src, "\xEF\xBB\xBF")) 3 else 0,
        };
    }

    pub fn next(self: *Tokenizer) SourceToken {
        var result: SourceToken = .{
            .tok = undefined,
            .span = .{
                .start = self.idx,
                .end = self.idx,
            },
        };
        state: switch (State.start) {
            .start => switch (self.src[self.idx]) {
                ' ', '\n', '\t', '\r' => {
                    self.idx += 1;
                    result.span.start = self.idx;
                    continue :state .start;
                },
                '(' => {
                    self.idx += 1;
                    result.tok = .l_paren;
                },
                ')' => {
                    self.idx += 1;
                    result.tok = .r_paren;
                },
                else => {
                    result.tok = .eof;
                },
            },
            else => {
                result.tok = .eof;
            },
        }
        return result;
    }
};

fn assertTokenize(src: [:0]const u8, tokens: []const Token) !void {
    var tokenizer = Tokenizer.init(src);
    for (tokens) |expected| {
        const s_token = tokenizer.next();
        try std.testing.expectEqual(s_token.tok, expected);
    }
    const last = tokenizer.next();
    try std.testing.expectEqual(Token.eof, last.tok);
    try std.testing.expectEqual(src.len, last.span.start);
    try std.testing.expectEqual(src.len, last.span.end);
}

test "tokenize parens" {
    try assertTokenize(" \n\t\r()", &.{
        .l_paren,
        .r_paren,
    });
}
