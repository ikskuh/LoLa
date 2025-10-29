const std = @import("std");

const ast = @import("ast.zig");

const Location = @import("location.zig").Location;
const Scope = @import("scope.zig").Scope;
const Diagnostics = @import("diagnostics.zig").Diagnostics;
const CompileUnit = @import("../common/CompileUnit.zig");
const CodeWriter = @import("code-writer.zig").CodeWriter;
const Instruction = @import("../common/ir.zig").Instruction;

const CodeGenError = error{
    OutOfMemory,
    AlreadyDeclared,
    TooManyVariables,
    TooManyLabels,
    LabelAlreadyDefined,
    Overflow,
    NotInLoop,
    VariableNotFound,
    InvalidStoreTarget,
};

/// Helper structure to emit debug symbols
const DebugSyms = struct {
    const Self = @This();

    writer: *CodeWriter,
    symbols: std.ArrayList(CompileUnit.DebugSymbol),
    allocator: std.mem.Allocator,

    fn push(self: *Self, location: Location) !void {
        try self.symbols.append(self.allocator, CompileUnit.DebugSymbol{
            .offset = @as(u32, @intCast(self.writer.code.items.len)),
            .sourceLine = location.line,
            .sourceColumn = @as(u16, @intCast(location.column)),
        });
    }
};

fn emitStore(debug_symbols: *DebugSyms, scope: *Scope, writer: *CodeWriter, expression: ast.Expression) CodeGenError!void {
    try debug_symbols.push(expression.location);
    std.debug.assert(expression.isAssignable());
    switch (expression.type) {
        .array_indexer => |indexer| {
            try emitExpression(debug_symbols, scope, writer, indexer.index.*); // load the index on the stack
            try emitExpression(debug_symbols, scope, writer, indexer.value.*); // load the array on the stack
            try writer.emitInstructionName(.array_store);
            try emitStore(debug_symbols, scope, writer, indexer.value.*); // now store back the value on the stack
        },

        .variable_expr => |variable_name| {
            if (std.mem.eql(u8, variable_name, "true")) {
                return error.InvalidStoreTarget;
            } else if (std.mem.eql(u8, variable_name, "false")) {
                return error.InvalidStoreTarget;
            } else if (std.mem.eql(u8, variable_name, "void")) {
                return error.InvalidStoreTarget;
            } else {
                const v = scope.get(variable_name) orelse return error.VariableNotFound;
                switch (v.type) {
                    .global => try writer.emitInstruction(Instruction{
                        .store_global_idx = .{ .value = v.storage_slot },
                    }),
                    .local => try writer.emitInstruction(Instruction{
                        .store_local = .{ .value = v.storage_slot },
                    }),
                }
            }
        },

        else => unreachable,
    }
}

fn emitExpression(debug_symbols: *DebugSyms, scope: *Scope, writer: *CodeWriter, expression: ast.Expression) CodeGenError!void {
    try debug_symbols.push(expression.location);
    switch (expression.type) {
        .array_indexer => |indexer| {
            try emitExpression(debug_symbols, scope, writer, indexer.index.*);
            try emitExpression(debug_symbols, scope, writer, indexer.value.*);
            try writer.emitInstructionName(.array_load);
        },

        .variable_expr => |variable_name| {
            if (std.mem.eql(u8, variable_name, "true")) {
                try writer.emitInstruction(Instruction{
                    .push_true = .{},
                });
            } else if (std.mem.eql(u8, variable_name, "false")) {
                try writer.emitInstruction(Instruction{
                    .push_false = .{},
                });
            } else if (std.mem.eql(u8, variable_name, "void")) {
                try writer.emitInstruction(Instruction{
                    .push_void = .{},
                });
            } else {
                const v = scope.get(variable_name) orelse return error.VariableNotFound;
                switch (v.type) {
                    .global => try writer.emitInstruction(Instruction{
                        .load_global_idx = .{ .value = v.storage_slot },
                    }),
                    .local => try writer.emitInstruction(Instruction{
                        .load_local = .{ .value = v.storage_slot },
                    }),
                }
            }
        },

        .array_literal => |array| {
            var i: usize = array.len;
            while (i > 0) {
                i -= 1;
                try emitExpression(debug_symbols, scope, writer, array[i]);
            }
            try writer.emitInstruction(Instruction{
                .array_pack = .{ .value = @as(u16, @intCast(array.len)) },
            });
        },

        .function_call => |call| {
            var i: usize = call.arguments.len;
            while (i > 0) {
                i -= 1;
                try emitExpression(debug_symbols, scope, writer, call.arguments[i]);
            }

            try writer.emitInstruction(Instruction{
                .call_fn = .{
                    .function = call.function.type.variable_expr,
                    .argc = @as(u8, @intCast(call.arguments.len)),
                },
            });
        },

        .method_call => |call| {
            // TODO: Write code in compiler.lola that covers this path.
            var i: usize = call.arguments.len;
            while (i > 0) {
                i -= 1;
                try emitExpression(debug_symbols, scope, writer, call.arguments[i]);
            }

            try emitExpression(debug_symbols, scope, writer, call.object.*);

            try writer.emitInstruction(Instruction{
                .call_obj = .{
                    .function = call.name,
                    .argc = @as(u8, @intCast(call.arguments.len)),
                },
            });
        },

        .number_literal => |literal| {
            try writer.emitInstruction(Instruction{
                .push_num = .{ .value = literal },
            });
        },

        .string_literal => |literal| {
            try writer.emitInstruction(Instruction{
                .push_str = .{ .value = literal },
            });
        },

        .unary_operator => |expr| {
            try emitExpression(debug_symbols, scope, writer, expr.value.*);
            try writer.emitInstructionName(switch (expr.operator) {
                .negate => .negate,
                .boolean_not => .bool_not,
            });
        },

        .binary_operator => |expr| {
            try emitExpression(debug_symbols, scope, writer, expr.lhs.*);
            try emitExpression(debug_symbols, scope, writer, expr.rhs.*);
            try writer.emitInstructionName(switch (expr.operator) {
                .add => .add,
                .subtract => .sub,
                .multiply => .mul,
                .divide => .div,
                .modulus => .mod,
                .boolean_or => .bool_or,
                .boolean_and => .bool_and,
                .less_than => .less,
                .greater_than => .greater,
                .greater_or_equal_than => .greater_eq,
                .less_or_equal_than => .less_eq,
                .equal => .eq,
                .different => .neq,
            });
        },
    }
}

fn emitStatement(debug_symbols: *DebugSyms, scope: *Scope, writer: *CodeWriter, stmt: ast.Statement) CodeGenError!void {
    try debug_symbols.push(stmt.location);

    switch (stmt.type) {
        .empty => {
            // trivial: do nothing!
        },
        .assignment => |ass| {
            try emitExpression(debug_symbols, scope, writer, ass.value);
            try emitStore(debug_symbols, scope, writer, ass.target);
        },
        .discard_value => |expr| {
            try emitExpression(debug_symbols, scope, writer, expr);
            try writer.emitInstruction(Instruction{
                .pop = .{},
            });
        },
        .return_void => {
            try writer.emitInstruction(Instruction{
                .ret = .{},
            });
        },
        .return_expr => |expr| {
            try emitExpression(debug_symbols, scope, writer, expr);
            try writer.emitInstruction(Instruction{
                .retval = .{},
            });
        },
        .while_loop => |loop| {
            const cont_lbl = try writer.createAndDefineLabel();
            const break_lbl = try writer.createLabel();

            try writer.pushLoop(break_lbl, cont_lbl);

            try emitExpression(debug_symbols, scope, writer, loop.condition);

            try writer.emitInstructionName(.jif);
            try writer.emitLabel(break_lbl);

            try emitStatement(debug_symbols, scope, writer, loop.body.*);

            try writer.emitInstructionName(.jmp);
            try writer.emitLabel(cont_lbl);

            try writer.defineLabel(break_lbl);

            writer.popLoop();
        },
        .for_loop => |loop| {
            try scope.enter();

            try emitExpression(debug_symbols, scope, writer, loop.source);

            try writer.emitInstructionName(.iter_make);

            // Loop variable is a constant!
            try scope.declare(loop.variable, true);

            const loopvar = scope.get(loop.variable) orelse unreachable;
            std.debug.assert(loopvar.type == .local);

            const loop_start = try writer.createAndDefineLabel();
            const loop_end = try writer.createLabel();

            try writer.pushLoop(loop_end, loop_start);

            try writer.emitInstructionName(.iter_next);

            try writer.emitInstructionName(.jif);
            try writer.emitLabel(loop_end);

            try writer.emitInstruction(Instruction{
                .store_local = .{
                    .value = loopvar.storage_slot,
                },
            });

            try emitStatement(debug_symbols, scope, writer, loop.body.*);

            try writer.emitInstructionName(.jmp);
            try writer.emitLabel(loop_start);

            try writer.defineLabel(loop_end);

            writer.popLoop();

            // // erase the iterator from the stack
            try writer.emitInstructionName(.pop);

            try scope.leave();
        },
        .if_statement => |conditional| {
            const end_if = try writer.createLabel();

            try emitExpression(debug_symbols, scope, writer, conditional.condition);

            if (conditional.false_body) |false_body| {
                const false_lbl = try writer.createLabel();

                try writer.emitInstructionName(.jif);
                try writer.emitLabel(false_lbl);

                try emitStatement(debug_symbols, scope, writer, conditional.true_body.*);

                try writer.emitInstructionName(.jmp);
                try writer.emitLabel(end_if);

                try writer.defineLabel(false_lbl);

                try emitStatement(debug_symbols, scope, writer, false_body.*);
            } else {
                try writer.emitInstructionName(.jif);
                try writer.emitLabel(end_if);

                try emitStatement(debug_symbols, scope, writer, conditional.true_body.*);
            }
            try writer.defineLabel(end_if);
        },
        .declaration => |decl| {
            try scope.declare(decl.variable, decl.is_const);

            if (decl.initial_value) |value| {
                try emitExpression(debug_symbols, scope, writer, value);
                const v = scope.get(decl.variable) orelse unreachable;
                switch (v.type) {
                    .local => try writer.emitInstruction(Instruction{
                        .store_local = .{
                            .value = v.storage_slot,
                        },
                    }),
                    .global => try writer.emitInstruction(Instruction{
                        .store_global_idx = .{
                            .value = v.storage_slot,
                        },
                    }),
                }
            }
        },
        .block => |blk| {
            try scope.enter();
            for (blk) |s| {
                try emitStatement(debug_symbols, scope, writer, s);
            }
            try scope.leave();
        },
        .@"break" => {
            try writer.emitBreak();
        },
        .@"continue" => {
            try writer.emitContinue();
        },
    }
}

/// Generates code for a given program. The program is assumed to be sane and checked with
/// code analysis already.
pub fn generateIR(
    allocator: std.mem.Allocator,
    program: ast.Program,
    comment: []const u8,
) !CompileUnit {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var writer = CodeWriter.init(allocator);
    defer writer.deinit();

    var functions = std.ArrayList(CompileUnit.Function).empty;
    defer functions.deinit(allocator);

    var debug_symbols = DebugSyms{
        .allocator = allocator,
        .writer = &writer,
        .symbols = std.ArrayList(CompileUnit.DebugSymbol).empty,
    };
    defer debug_symbols.symbols.deinit(allocator);

    var global_scope = Scope.init(allocator, null, true);
    defer global_scope.deinit();

    for (program.root_script) |stmt| {
        try emitStatement(&debug_symbols, &global_scope, &writer, stmt);
    }

    // each script ends with a return
    try writer.emitInstruction(Instruction{
        .ret = .{},
    });

    std.debug.assert(global_scope.return_point.items.len == 0);

    for (program.functions) |function| {
        const entry_point = @as(u32, @intCast(writer.code.items.len));

        var local_scope = Scope.init(allocator, &global_scope, false);
        defer local_scope.deinit();

        for (function.parameters) |param| {
            try local_scope.declare(param, true);
        }

        try emitStatement(&debug_symbols, &local_scope, &writer, function.body);

        // when no explicit return is given, we implicitly return void
        try writer.emitInstruction(Instruction{
            .ret = .{},
        });

        try functions.append(allocator, CompileUnit.Function{
            .name = try arena.allocator().dupe(u8, function.name),
            .entryPoint = entry_point,
            .localCount = @as(u16, @intCast(local_scope.max_locals)),
        });
    }

    const code = try writer.finalize();
    defer allocator.free(code);

    std.sort.block(CompileUnit.DebugSymbol, debug_symbols.symbols.items, {}, struct {
        fn lessThan(v: void, lhs: CompileUnit.DebugSymbol, rhs: CompileUnit.DebugSymbol) bool {
            _ = v;
            return lhs.offset < rhs.offset;
        }
    }.lessThan);

    var cu = CompileUnit{
        .comment = try arena.allocator().dupe(u8, comment),
        .globalCount = @as(u16, @intCast(global_scope.global_variables.items.len)),
        .temporaryCount = @as(u16, @intCast(global_scope.max_locals)),
        .code = try arena.allocator().dupe(u8, code),
        .functions = try arena.allocator().dupe(CompileUnit.Function, functions.items),
        .debugSymbols = try arena.allocator().dupe(CompileUnit.DebugSymbol, debug_symbols.symbols.items),

        .arena = undefined,
    };
    // this prevents miscompilation of undefined evaluation order in init statement.
    // we need to use the arena for allocation above, so we change it.
    cu.arena = arena;

    return cu;
}

test "code generation" {
    // For lack of a better idea:
    // Just run the analysis against the compiler test suite
    var diagnostics = Diagnostics.init(std.testing.allocator);
    defer diagnostics.deinit();

    const seq = try @import("tokenizer.zig").tokenize(std.testing.allocator, &diagnostics, "src/test/compiler.lola", @embedFile("compiler.lola"));
    defer std.testing.allocator.free(seq);

    var pgm = try @import("parser.zig").parse(std.testing.allocator, &diagnostics, seq);
    defer pgm.deinit();

    var compile_unit = try generateIR(std.testing.allocator, pgm, "test unit");
    defer compile_unit.deinit();

    try std.testing.expectEqual(@as(usize, 0), diagnostics.messages.items.len);

    try std.testing.expectEqualStrings("test unit", compile_unit.comment);
}
