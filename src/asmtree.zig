const std = @import("std");
const mem = std.mem;

const ast = @import("ast.zig");
const lex = @import("lex.zig");

const Program = struct {
    function: Function,
};

const Function = struct {
    name: []const u8,
    instructions: std.ArrayList(Instruction),
};

const SrcDest = struct {
    src: Operand,
    dest: Operand,
};

const Instruction = union(enum) {
    mov: SrcDest,
    ret,
};

const Operand = union(enum) {
    imm: i32,
    reg: Register,
};

const Register = enum {
    eax,
};

const AsmTree = struct {
    arena: std.heap.ArenaAllocator,
    alloc: mem.Allocator,
    function: Function,

    pub fn init() AsmTree {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        return .{
            .arena = arena,
            .alloc = arena.allocator(),
            .function = undefined,
        };
    }

    pub fn deinit(self: *AsmTree) void {
        self.arena.deinit();
    }

    /// Returns processed assembly syntax tree. Freed by calling deinit() on the returned struct.
    pub fn from(ast_ref: ast.Ast) !AsmTree {
        var ast_tree = AsmTree.init();
        try ast_tree.processRoot(ast_ref.function);
        return ast_tree;
    }

    fn processRoot(self: *AsmTree, function: ast.Function) !void {
        const instructions = try self.convertFnBody(function.body);
        const processed_functinon = Function{
            .name = function.identifier,
            .instructions = instructions,
        };
        self.function = processed_functinon;
    }

    fn convertFnBody(self: *AsmTree, body: std.ArrayList(ast.Statement)) !std.ArrayList(Instruction) {
        var instrs = std.ArrayList(Instruction).init(self.alloc);
        for (body.items) |stmt| {
            // Convert statement
            switch (stmt) {
                .st_return => |expr| {
                    const mov = Instruction{ .mov = SrcDest{
                        .src = self.convertExpr(expr),
                        .dest = .{ .reg = .eax },
                    } };
                    try instrs.append(mov);
                    try instrs.append(.ret);
                },
            }
        }

        return instrs;
    }

    fn convertExpr(self: *AsmTree, expr: ast.Expr) Operand {
        _ = self;
        switch (expr) {
            .constant => |val| {
                return .{ .imm = val };
            },
        }
    }
};

test "convert to ast tree for simple program" {
    const expect = std.testing.expect;

    const program =
        \\int main(void) {
        \\    return 1;
        \\}
    ;
    var tokenizer = lex.Tokenizer.init(program);
    var parser = ast.Parser.init(&tokenizer);
    const ast_res = try parser.parse();
    const asm_tree = try AsmTree.from(ast_res);

    try expect(mem.eql(u8, asm_tree.function.name, "main"));
    switch (asm_tree.function.instructions.items[0]) {
        .mov => |srcdest| {
            switch (srcdest.src) {
                .imm => |val| try expect(val == 1),
                else => return error.Fail,
            }
        },
        else => return error.Fail,
    }
}
