const std = @import("std");
const mem = std.mem;
const lex = @import("lex.zig");

const ast_log = std.log.scoped(.PARSE);

/// Root node of the C AST
pub const Ast = union(enum) {
    function: Function,
};

/// Basic function AST node
pub const Function = struct {
    /// function name
    identifier: []const u8,
    /// function body
    body: std.ArrayList(Statement),
};

/// AST node for a singular line of C source text deliniated by a semicolon
pub const Statement = union(enum) {
    /// return statement
    st_return: Expr,
};

/// AST node for an evaluatable expression
pub const Expr = union(enum) {
    /// int
    constant: i32,
};

const ParseErr = error{
    UnexpectedToken,
    InvalidConstant,
    OutOfMemory,
};

pub const Parser = struct {
    tokenizer: *lex.Tokenizer,
    src: []const u8,
    arena: std.heap.ArenaAllocator,
    alloc: mem.Allocator,

    pub fn init(tokenizer: *lex.Tokenizer) Parser {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        return .{
            .tokenizer = tokenizer,
            .src = tokenizer.src,
            .arena = arena,
            .alloc = arena.allocator(),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.arena.deinit();
    }

    fn next(self: *Parser) lex.SourceToken {
        return self.tokenizer.next();
    }

    fn expect(self: *Parser, tok: lex.Token) ParseErr!lex.SourceToken {
        const s_tok = self.next();
        if (tok == s_tok.tok) {
            return s_tok;
        } else {
            logUnexpected(tok, s_tok.tok);
            return ParseErr.UnexpectedToken;
        }
    }

    // Saves having to write _ = two dozen times
    fn expectSemantic(self: *Parser, tok: lex.Token) ParseErr!void {
        _ = try self.expect(tok);
    }

    fn logUnexpected(expected: lex.Token, actual: lex.Token) void {
        ast_log.err("Expected {}, found {}", .{ expected, actual });
    }

    // TODO: Display line on which error occured as well as pointer to token start

    fn expectFn(self: *Parser) ParseErr!Function {
        try self.expectSemantic(.kw_int);
        const ident = (try self.expect(.identifier)).span.toSrcSlice(self.src);
        try self.expectSemantic(.l_paren);
        try self.expectSemantic(.kw_void);
        try self.expectSemantic(.r_paren);
        try self.expectSemantic(.l_brace);
        const body_stmt = try self.expectStatement();
        // Needs alloc
        var body = std.ArrayList(Statement).init(self.alloc);
        body.append(body_stmt) catch return ParseErr.OutOfMemory;
        try self.expectSemantic(.r_brace);

        return Function{
            .identifier = ident,
            .body = body,
        };
    }

    fn expectStatement(self: *Parser) ParseErr!Statement {
        try self.expectSemantic(.kw_return);
        const expr = try self.expectExpr();
        try self.expectSemantic(.semicolon);

        return Statement{ .st_return = expr };
    }

    fn expectExpr(self: *Parser) ParseErr!Expr {
        const int_tok = try self.expect(.int_constant);
        const tok_span = int_tok.span.toSrcSlice(self.src);
        const parsed_int = std.fmt.parseInt(i32, tok_span, 10) catch return ParseErr.InvalidConstant;
        return Expr{ .constant = parsed_int };
    }

    pub fn parse(self: *Parser) ParseErr!Ast {
        const func: Function = try self.expectFn();
        try self.expectSemantic(.eof);
        return Ast{ .function = func };
    }
};

test "parse small program" {
    const program =
        \\int foock(void) {
        \\    return 2;
        \\}
    ;
    var tokenizer = lex.Tokenizer.init(program);
    var parser = Parser.init(&tokenizer);
    const ast = try parser.parse();

    try std.testing.expect(mem.eql(u8, ast.function.identifier, "foock"));
}

test "parse expression" {
    var tokenizer = lex.Tokenizer.init("return 25;");
    var parser = Parser.init(&tokenizer);
    const stmt = try parser.expectStatement();

    switch (stmt) {
        .st_return => |expr| try std.testing.expect(expr.constant == 25),
    }
}
