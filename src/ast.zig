const std = @import("std");
const mem = std.mem;
const lex = @import("lex.zig");

const ast_log = std.log.scoped(.PARSE);

/// Root node of the C AST
const Ast = union(enum) {
    function: Function,
};

/// Basic function AST node
const Function = struct {
    /// function name
    identifier: []const u8,
    /// function body
    body: Statement,
};

/// AST node for a singular line of C source text deliniated by a semicolon
const Statement = union(enum) {
    /// return statement
    st_return: Expr,
};

/// AST node for an evaluatable expression
const Expr = union(enum) {
    /// int
    constant: i32,
};

const ParseErr = error{
    UnexpectedToken,
};

pub const Parser = struct {
    tokenizer: *lex.Tokenizer,
    src: []const u8,

    pub fn init(tokenizer: *lex.Tokenizer) Parser {
        return .{
            .tokenizer = tokenizer,
            .src = tokenizer.src,
        };
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
        const body = try self.expectStatement();
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
        // TODO: This does not parse numeric value
        try self.expectSemantic(.int_constant);
        return Expr{ .constant = 2 };
    }

    pub fn tryParse(self: *Parser) ParseErr!Ast {
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
    const ast = try parser.tryParse();

    try std.testing.expect(mem.eql(u8, ast.function.identifier, "foock"));
}
