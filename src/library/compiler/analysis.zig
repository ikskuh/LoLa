const std = @import("std");

const ast = @import("ast.zig");

const Location = @import("location.zig").Location;
const Scope = @import("scope.zig").Scope;
const Diagnostics = @import("diagnostics.zig").Diagnostics;
const Type = @import("typeset.zig").Type;
const TypeSet = @import("typeset.zig").TypeSet;

const AnalysisState = struct {
    /// Depth of nested loops (while, for)
    loop_nesting: usize,

    /// Depth of nested conditionally executed scopes (if, while, for)
    conditional_scope_depth: usize,

    /// Only `true` when not analyzing a function
    is_root_script: bool,
};

const ValidationError = error{OutOfMemory};

const array_or_string = TypeSet.init(.{ .array, .string });

fn expressionTypeToString(src: ast.Expression.Type) []const u8 {
    return switch (src) {
        .array_indexer => "array indexer",
        .variable_expr => "variable",
        .array_literal => "array literal",
        .function_call => "function call",
        .method_call => "method call",
        .number_literal => "number literal",
        .string_literal => "string literal",
        .unary_operator => "unary operator application",
        .binary_operator => "binary operator application",
    };
}

fn emitTooManyVariables(diagnostics: *Diagnostics, location: Location) !void {
    try diagnostics.emit(.@"error", location, "Too many variables declared! The maximum allowed number of variables is 35535.", .{});
}

fn performTypeCheck(diagnostics: *Diagnostics, location: Location, expected: TypeSet, actual: TypeSet) !void {
    if (expected.intersection(actual).isEmpty()) {
        try diagnostics.emit(.warning, location, "Possible type mismatch detected: Expected {f}, found {f}", .{
            expected,
            actual,
        });
    }
}

/// Validates a expression and returns a set of possible result types.
fn validateExpression(state: *AnalysisState, diagnostics: *Diagnostics, scope: *Scope, expression: ast.Expression) ValidationError!TypeSet {
    // we're happy for now with expressions...
    switch (expression.type) {
        .array_indexer => |indexer| {
            const array_type = try validateExpression(state, diagnostics, scope, indexer.value.*);
            const index_type = try validateExpression(state, diagnostics, scope, indexer.index.*);

            try performTypeCheck(diagnostics, indexer.value.location, array_or_string, array_type);
            try performTypeCheck(diagnostics, indexer.index.location, TypeSet.from(.number), index_type);

            if (array_type.contains(.array)) {
                // when we're possibly indexing an array,
                // we return a value of type `any`
                return TypeSet.any;
            } else if (array_type.contains(.string)) {
                // when we are not an array, but a string,
                // we can only return a number.
                return TypeSet.from(.number);
            } else {
                return TypeSet.empty;
            }
        },

        .variable_expr => |variable_name| {

            // Check reserved names
            if (std.mem.eql(u8, variable_name, "true")) {
                return TypeSet.from(.boolean);
            } else if (std.mem.eql(u8, variable_name, "false")) {
                return TypeSet.from(.boolean);
            } else if (std.mem.eql(u8, variable_name, "void")) {
                return TypeSet.from(.void);
            }

            const variable = scope.get(variable_name) orelse {
                try diagnostics.emit(.@"error", expression.location, "Use of undeclared variable {s}", .{
                    variable_name,
                });
                return TypeSet.any;
            };

            return variable.possible_types;
        },

        .array_literal => |array| {
            for (array) |item| {
                _ = try validateExpression(state, diagnostics, scope, item);
            }
            return TypeSet.from(.array);
        },

        .function_call => |call| {
            if (call.function.type != .variable_expr) {
                try diagnostics.emit(.@"error", expression.location, "Function name expected", .{});
            }

            if (call.arguments.len >= 256) {
                try diagnostics.emit(.@"error", expression.location, "Function argument list exceeds 255 arguments!", .{});
            }

            for (call.arguments) |item| {
                _ = try validateExpression(state, diagnostics, scope, item);
            }

            return TypeSet.any;
        },

        .method_call => |call| {
            _ = try validateExpression(state, diagnostics, scope, call.object.*);
            for (call.arguments) |item| {
                _ = try validateExpression(state, diagnostics, scope, item);
            }

            return TypeSet.any;
        },

        .number_literal => {
            // these are always ok
            return TypeSet.from(.number);
        },

        .string_literal => {
            return TypeSet.from(.string);
        },

        .unary_operator => |expr| {
            const result = try validateExpression(state, diagnostics, scope, expr.value.*);

            const expected = switch (expr.operator) {
                .negate => Type.number,
                .boolean_not => Type.boolean,
            };

            try performTypeCheck(diagnostics, expression.location, TypeSet.from(expected), result);

            return result;
        },

        .binary_operator => |expr| {
            const lhs = try validateExpression(state, diagnostics, scope, expr.lhs.*);
            const rhs = try validateExpression(state, diagnostics, scope, expr.rhs.*);

            const accepted_set = switch (expr.operator) {
                .add => TypeSet.init(.{ .string, .number, .array }),
                .subtract, .multiply, .divide, .modulus => TypeSet.from(.number),
                .boolean_or, .boolean_and => TypeSet.from(.boolean),
                .equal, .different => TypeSet.any,
                .less_than, .greater_than, .greater_or_equal_than, .less_or_equal_than => TypeSet.init(.{ .string, .number, .array }),
            };

            try performTypeCheck(diagnostics, expr.lhs.location, accepted_set, lhs);
            try performTypeCheck(diagnostics, expr.rhs.location, accepted_set, rhs);

            if (!TypeSet.areCompatible(lhs, rhs)) {
                try diagnostics.emit(.warning, expression.location, "Possible type mismatch detected. {f} and {f} are not compatible.\n", .{
                    lhs,
                    rhs,
                });
                return TypeSet.empty;
            }

            return switch (expr.operator) {
                .add => TypeSet.intersection(lhs, rhs),
                .subtract, .multiply, .divide, .modulus => TypeSet.from(.number),
                .boolean_or, .boolean_and => TypeSet.from(.boolean),
                .less_than, .greater_than, .greater_or_equal_than, .less_or_equal_than, .equal, .different => TypeSet.from(.boolean),
            };
        },
    }
    return .void;
}

fn validateStore(state: *AnalysisState, diagnostics: *Diagnostics, scope: *Scope, expression: ast.Expression, type_hint: TypeSet) ValidationError!void {
    if (!expression.isAssignable()) {
        try diagnostics.emit(.@"error", expression.location, "Expected array indexer or a variable, got {s}", .{
            expressionTypeToString(expression.type),
        });
        return;
    }

    switch (expression.type) {
        .array_indexer => |indexer| {
            const array_val = try validateExpression(state, diagnostics, scope, indexer.value.*);
            const index_val = try validateExpression(state, diagnostics, scope, indexer.index.*);

            try performTypeCheck(diagnostics, indexer.value.location, array_or_string, array_val);
            try performTypeCheck(diagnostics, indexer.index.location, TypeSet.from(.number), index_val);

            if (array_val.contains(.string) and !array_val.contains(.array)) {
                // when we are sure we write into a string, but definitly not an array
                // check if we're writing a number.
                try performTypeCheck(diagnostics, expression.location, TypeSet.from(.number), type_hint);
            }

            // now propagate the store validation back to the lvalue.
            // Note that we can assume that the lvalue _is_ a array, as it would be a type mismatch otherwise.
            try validateStore(state, diagnostics, scope, indexer.value.*, array_or_string.intersection(array_val));
        },

        .variable_expr => |variable_name| {
            if (std.mem.eql(u8, variable_name, "true") or std.mem.eql(u8, variable_name, "false") or std.mem.eql(u8, variable_name, "void")) {
                try diagnostics.emit(.@"error", expression.location, "Expected array indexer or a variable, got {s}", .{
                    variable_name,
                });
            } else if (scope.get(variable_name)) |variable| {
                if (variable.is_const) {
                    try diagnostics.emit(.@"error", expression.location, "Assignment to constant {s} not allowed.", .{
                        variable_name,
                    });
                }

                if (state.conditional_scope_depth > 0) {
                    variable.possible_types = variable.possible_types.@"union"(type_hint);
                } else {
                    variable.possible_types = type_hint;
                }
            }
        },

        else => unreachable,
    }
}

fn validateStatement(state: *AnalysisState, diagnostics: *Diagnostics, scope: *Scope, stmt: ast.Statement) ValidationError!void {
    switch (stmt.type) {
        .empty => {
            // trivial: do nothing!
        },
        .assignment => |ass| {
            const value_type = try validateExpression(state, diagnostics, scope, ass.value);
            if (ass.target.isAssignable()) {
                try validateStore(state, diagnostics, scope, ass.target, value_type);
            } else {
                try diagnostics.emit(.@"error", ass.target.location, "Expected either a array indexer or a variable, got {s}", .{
                    @tagName(@as(ast.Expression.Type, ass.target.type)),
                });
            }
        },
        .discard_value => |expr| {
            _ = try validateExpression(state, diagnostics, scope, expr);
        },
        .return_void => {
            // this is always ok
        },
        .return_expr => |expr| {
            // this is ok when the expr is ok
            _ = try validateExpression(state, diagnostics, scope, expr);

            // and when we are not on the root script.
            if (state.is_root_script) {
                try diagnostics.emit(.@"error", stmt.location, "Returning a value from global scope is not allowed.", .{});
            }
        },
        .while_loop => |loop| {
            state.loop_nesting += 1;
            defer state.loop_nesting -= 1;

            state.conditional_scope_depth += 1;
            defer state.conditional_scope_depth -= 1;

            const condition_type = try validateExpression(state, diagnostics, scope, loop.condition);
            try validateStatement(state, diagnostics, scope, loop.body.*);

            try performTypeCheck(diagnostics, stmt.location, TypeSet.from(.boolean), condition_type);
        },
        .for_loop => |loop| {
            state.loop_nesting += 1;
            defer state.loop_nesting -= 1;

            state.conditional_scope_depth += 1;
            defer state.conditional_scope_depth -= 1;

            try scope.enter();

            scope.declare(loop.variable, true) catch |err| switch (err) {
                error.AlreadyDeclared => unreachable, // not possible for locals
                error.TooManyVariables => try emitTooManyVariables(diagnostics, stmt.location),
                else => |e| return e,
            };

            const array_type = try validateExpression(state, diagnostics, scope, loop.source);
            try validateStatement(state, diagnostics, scope, loop.body.*);

            try performTypeCheck(diagnostics, stmt.location, TypeSet.from(.array), array_type);

            try scope.leave();
        },
        .if_statement => |conditional| {
            state.conditional_scope_depth += 1;
            defer state.conditional_scope_depth -= 1;

            const conditional_type = try validateExpression(state, diagnostics, scope, conditional.condition);
            try validateStatement(state, diagnostics, scope, conditional.true_body.*);
            if (conditional.false_body) |body| {
                try validateStatement(state, diagnostics, scope, body.*);
            }

            try performTypeCheck(diagnostics, stmt.location, TypeSet.from(.boolean), conditional_type);
        },
        .declaration => |decl| {
            // evaluate expression before so we can safely reference up-variables:
            // var a = a * 2;
            const initial_value = if (decl.initial_value) |init_val|
                try validateExpression(state, diagnostics, scope, init_val)
            else
                null;

            scope.declare(decl.variable, decl.is_const) catch |err| switch (err) {
                error.AlreadyDeclared => try diagnostics.emit(.@"error", stmt.location, "Global variable {s} is already declared!", .{decl.variable}),
                error.TooManyVariables => try emitTooManyVariables(diagnostics, stmt.location),
                else => |e| return e,
            };

            if (initial_value) |init_val|
                scope.get(decl.variable).?.possible_types = init_val;

            if (decl.is_const and decl.initial_value == null) {
                try diagnostics.emit(.@"error", stmt.location, "Constant {s} must be initialized!", .{
                    decl.variable,
                });
            }
        },
        .block => |blk| {
            try scope.enter();
            for (blk) |sub_stmt| {
                try validateStatement(state, diagnostics, scope, sub_stmt);
            }
            try scope.leave();
        },
        .@"break" => {
            if (state.loop_nesting == 0) {
                try diagnostics.emit(.@"error", stmt.location, "break outside of loop!", .{});
            }
        },
        .@"continue" => {
            if (state.loop_nesting == 0) {
                try diagnostics.emit(.@"error", stmt.location, "continue outside of loop!", .{});
            }
        },
    }
}

fn getErrorCount(diagnostics: *const Diagnostics) usize {
    var res: usize = 0;
    for (diagnostics.messages.items) |msg| {
        if (msg.kind == .@"error")
            res += 1;
    }
    return res;
}

/// Validates the `program` against programming mistakes and filles `diagnostics` with the findings.
/// Note that the function will always succeed when no `OutOfMemory` happens. To see if the program
/// is semantically sound, check `diagnostics` for error messages.
pub fn validate(allocator: std.mem.Allocator, diagnostics: *Diagnostics, program: ast.Program) ValidationError!bool {
    var global_scope = Scope.init(allocator, null, true);
    defer global_scope.deinit();

    const initial_errc = getErrorCount(diagnostics);

    for (program.root_script) |stmt| {
        var state = AnalysisState{
            .loop_nesting = 0,
            .is_root_script = true,
            .conditional_scope_depth = 0,
        };

        try validateStatement(&state, diagnostics, &global_scope, stmt);
    }

    std.debug.assert(global_scope.return_point.items.len == 0);

    for (program.functions, 0..) |function, i| {
        for (program.functions[0..i]) |other_fn| {
            if (std.mem.eql(u8, function.name, other_fn.name)) {
                try diagnostics.emit(.@"error", function.location, "A function with the name {s} was already declared!", .{function.name});
                break;
            }
        }

        var local_scope = Scope.init(allocator, &global_scope, false);
        defer local_scope.deinit();

        for (function.parameters) |param| {
            local_scope.declare(param, true) catch |err| switch (err) {
                error.AlreadyDeclared => try diagnostics.emit(.@"error", function.location, "A parameter {s} is already declared!", .{param}),
                error.TooManyVariables => try emitTooManyVariables(diagnostics, function.location),
                else => |e| return e,
            };
        }

        var state = AnalysisState{
            .loop_nesting = 0,
            .is_root_script = false,
            .conditional_scope_depth = 0,
        };
        try validateStatement(&state, diagnostics, &local_scope, function.body);
    }

    return (getErrorCount(diagnostics) == initial_errc);
}

test "validate correct program" {
    // For lack of a better idea:
    // Just run the analysis against the compiler test suite
    var diagnostics = Diagnostics.init(std.testing.allocator);
    defer diagnostics.deinit();

    const seq = try @import("tokenizer.zig").tokenize(std.testing.allocator, &diagnostics, "src/test/compiler.lola", @embedFile("compiler.lola"));
    defer std.testing.allocator.free(seq);

    var pgm = try @import("parser.zig").parse(std.testing.allocator, &diagnostics, seq);
    defer pgm.deinit();

    try std.testing.expectEqual(true, try validate(std.testing.allocator, &diagnostics, pgm));

    for (diagnostics.messages.items) |msg| {
        std.debug.print("{s}\n", .{msg});
    }

    try std.testing.expectEqual(@as(usize, 0), diagnostics.messages.items.len);
}

fn expectAnalysisErrors(source: []const u8, expected_messages: []const []const u8) !void {
    // For lack of a better idea:
    // Just run the analysis against the compiler test suite
    var diagnostics = Diagnostics.init(std.testing.allocator);
    defer diagnostics.deinit();

    const seq = try @import("tokenizer.zig").tokenize(std.testing.allocator, &diagnostics, "", source);
    defer std.testing.allocator.free(seq);

    var pgm = try @import("parser.zig").parse(std.testing.allocator, &diagnostics, seq);
    defer pgm.deinit();

    try std.testing.expectEqual(false, try validate(std.testing.allocator, &diagnostics, pgm));

    try std.testing.expectEqual(expected_messages.len, diagnostics.messages.items.len);
    for (expected_messages, 0..) |expected, i| {
        try std.testing.expectEqualStrings(expected, diagnostics.messages.items[i].message);
    }
}

test "detect return from root script" {
    try expectAnalysisErrors("return 10;", &[_][]const u8{
        "Returning a value from global scope is not allowed.",
    });
}

test "detect const without init" {
    try expectAnalysisErrors("const a;", &[_][]const u8{
        "Constant a must be initialized!",
    });
}

test "detect assignment to const" {
    try expectAnalysisErrors("const a = 5; a = 10;", &[_][]const u8{
        "Assignment to constant a not allowed.",
    });
}

test "detect doubly-declared global variables" {
    try expectAnalysisErrors("var a; var a;", &[_][]const u8{
        "Global variable a is already declared!",
    });
}

test "detect assignment to const parameter" {
    try expectAnalysisErrors("function f(x) { x = void; }", &[_][]const u8{
        "Assignment to constant x not allowed.",
    });
}
