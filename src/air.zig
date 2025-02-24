const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;

const ast = @import("ast.zig");
const lex = @import("lex.zig");

/// Write assembly corresponding to AIR to an output stream
pub fn emitToFile(air_in: Air, writer: std.io.AnyWriter) !void {
    try air_in.function.writeAsm(writer);
}

const Program = struct {
    function: Function,
};

const Function = struct {
    name: []const u8,
    instructions: std.ArrayList(Instruction),

    pub fn writeAsm(self: Function, writer: std.io.AnyWriter) !void {
        const is_mac: bool = comptime builtin.os.tag == .macos;
        // Functions need prepending _ on macos
        const format = comptime if (is_mac) "\t.globl _{s}\n_{s}:\n" else "\t.globl {s}\n{s}:\n";

        try writer.print(format, .{ self.name, self.name });
        for (self.instructions.items) |instr| {
            try instr.writeAsm(writer);
        }

        // Required prologue on linux for non-executable stack
        if (!is_mac) _ = try writer.write(".section .note.GNU-stack,\"\",@progbits");
    }
};

const Instruction = union(enum) {
    mov: SrcDest,
    ret: void,

    pub fn writeAsm(self: Instruction, writer: std.io.AnyWriter) !void {
        switch (self) {
            .mov => |srcdest| {
                _ = try writer.write("\tmovl\t");
                try srcdest.src.writeAsm(writer);
                _ = try writer.write(", ");
                try srcdest.dest.writeAsm(writer);
                _ = try writer.write("\n");
            },
            .ret => {
                _ = try writer.write("\tret\n");
            },
        }
    }
};

const SrcDest = struct {
    src: Operand,
    dest: Operand,
};

const Operand = union(enum) {
    imm: i32,
    reg: Register,

    pub fn writeAsm(self: Operand, writer: std.io.AnyWriter) !void {
        switch (self) {
            .imm => |val| {
                try writer.print("${d}", .{val});
            },
            .reg => |reg| {
                _ = try writer.write(reg.toSlice());
            },
        }
    }
};

const Register = enum {
    eax,

    pub fn toSlice(self: Register) []const u8 {
        switch (self) {
            .eax => return "%eax",
        }
    }
};

pub const Air = struct {
    arena: std.heap.ArenaAllocator,
    function: Function,

    /// Creates an arena allocator
    fn init() Air {
        return .{
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
            .function = undefined,
        };
    }

    /// Destroys underlying arena allocator
    pub fn deinit(self: *Air) void {
        self.arena.deinit();
    }

    /// Returns processed assembly syntax tree. Creates arena allocator which is freed by calling deinit() on the returned struct.
    pub fn from(ast_ref: ast.Ast) !Air {
        var ast_tree = Air.init();
        try ast_tree.processRoot(ast_ref.function);
        return ast_tree;
    }

    fn processRoot(self: *Air, function: ast.Function) !void {
        const instructions = try self.convertFnBody(function.body);
        std.debug.assert(instructions.getLast() == .ret);
        const processed_function = Function{
            .name = function.identifier,
            .instructions = instructions,
        };
        self.function = processed_function;
    }

    fn convertFnBody(self: *Air, body: std.ArrayList(ast.Statement)) !std.ArrayList(Instruction) {
        var instrs = std.ArrayList(Instruction).init(self.arena.allocator());
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

    fn convertExpr(self: *Air, expr: ast.Expr) Operand {
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
    const asm_tree = try Air.from(ast_res);

    try expect(mem.eql(u8, asm_tree.function.name, "main"));
    const instrs = asm_tree.function.instructions;
    try expect(instrs.items.len == 2);
    std.debug.assert(instrs.getLast() == .ret);
    switch (instrs.items[0]) {
        .mov => |srcdest| {
            switch (srcdest.src) {
                .imm => |val| try expect(val == 1),
                else => return error.Fail,
            }
            switch (srcdest.dest) {
                .reg => {},
                else => return error.Fail,
            }
        },
        else => return error.Fail,
    }
}
