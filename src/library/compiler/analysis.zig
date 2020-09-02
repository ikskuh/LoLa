const std = @import("std");

const ast = @import("ast.zig");

const Location = @import("location.zig").Location;
const Scope = @import("scope.zig").Scope;
const Diagnostics = @import("diagnostics.zig").Diagnostics;

const AnalysisState = struct {
    loop_nesting: usize,
};

const Type = enum {
    @"void",
    number,
    string,
    boolean,
    array,
    object,

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writerAll(@tagName(value));
    }
};

const TypeSet = struct {
    const Self = @This();

    pub const empty = Self{
        .@"void" = false,
        .number = false,
        .string = false,
        .boolean = false,
        .array = false,
        .object = false,
    };

    pub const any = Self{
        .@"void" = true,
        .number = true,
        .string = true,
        .boolean = true,
        .array = true,
        .object = true,
    };

    @"void": bool,
    number: bool,
    string: bool,
    boolean: bool,
    array: bool,
    object: bool,

    fn from(value_type: Type) Self {
        return Self{
            .@"void" = (value_type == .@"void"),
            .number = (value_type == .number),
            .string = (value_type == .string),
            .boolean = (value_type == .boolean),
            .array = (value_type == .array),
            .object = (value_type == .object),
        };
    }

    fn contains(self: Self, item: Type) bool {
        return switch (item) {
            .@"void" => self.@"void",
            .number => self.number,
            .string => self.string,
            .boolean => self.boolean,
            .array => self.array,
            .object => self.object,
        };
    }

    /// Returns a type set that only contains all types that are contained in both parameters.
    fn intersection(a: Self, b: Self) Self {
        var result: Self = undefined;
        inline for (std.meta.fields(Self)) |fld| {
            @field(result, fld.name) = @field(a, fld.name) and @field(b, fld.name);
        }
        return result;
    }

    /// Returns a type set that contains all types that are contained in any of the parameters.
    fn @"union"(a: Self, b: Self) Self {
        var result: Self = undefined;
        inline for (std.meta.fields(Self)) |fld| {
            @field(result, fld.name) = @field(a, fld.name) or @field(b, fld.name);
        }
        return result;
    }

    fn isEmpty(self: Self) bool {
        inline for (std.meta.fields(Self)) |fld| {
            if (@field(self, fld.name))
                return false;
        }
        return true;
    }

    fn isAny(self: Self) bool {
        inline for (std.meta.fields(Self)) |fld| {
            if (!@field(self, fld.name))
                return false;
        }
        return true;
    }

    /// Tests if the type set contains at least one common type.
    fn areCompatible(a: Self, b: Self) bool {
        return !intersection(a, b).isEmpty();
    }

    pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        if (value.isEmpty()) {
            try writer.writeAll("none");
        } else if (value.isAny()) {
            try writer.writeAll("any");
        } else {
            var separate = false;
            inline for (std.meta.fields(Self)) |fld| {
                if (@field(value, fld.name)) {
                    if (separate) {
                        try writer.writeAll("|");
                    }
                    separate = true;
                    try writer.writeAll(fld.name);
                }
            }
        }
    }
};

const ValidationError = error{OutOfMemory};

fn emitTooManyVariables(diagnostics: *Diagnostics, location: Location) !void {
    try diagnostics.emit(.@"error", location, "Too many variables declared! The maximum allowed number of variables is 35535.", .{});
}

fn performTypeCheck(diagnostics: *Diagnostics, location: Location, expected: TypeSet, actual: TypeSet) !void {
    if (expected.intersection(actual).isEmpty()) {
        try diagnostics.emit(.warning, location, "Possible type mismatch detected: Expected {}, found {}", .{
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

            try performTypeCheck(diagnostics, indexer.value.location, TypeSet.from(.array), array_type);
            try performTypeCheck(diagnostics, indexer.index.location, TypeSet.from(.number), array_type);

            return TypeSet.any;
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

            _ = scope.get(variable_name) orelse {
                try diagnostics.emit(.@"error", expression.location, "Use of undeclared variable {}", .{
                    variable_name,
                });
            };

            // TODO: Return annotated type set from variable.

            return TypeSet.any;
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

        .number_literal => |expr| {
            // these are always ok
            return TypeSet.from(.number);
        },

        .string_literal => |literal| {
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

            if (!TypeSet.areCompatible(lhs, rhs)) {
                try diagnostics.emit(.warning, expression.location, "Possible type mismatch detected. {} and {} are not compatible.\n", .{
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

fn validateStatement(state: *AnalysisState, diagnostics: *Diagnostics, scope: *Scope, stmt: ast.Statement) ValidationError!void {
    switch (stmt.type) {
        .empty => {
            // trivial: do nothing!
        },
        .assignment => |ass| {
            if (!ass.target.isAssignable()) {
                try diagnostics.emit(.@"error", ass.target.location, "Expected either a array indexer or a variable, got {}", .{
                    @tagName(@as(ast.Expression.Type, ass.target.type)),
                });
            }

            _ = try validateExpression(state, diagnostics, scope, ass.target);
            _ = try validateExpression(state, diagnostics, scope, ass.value);
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
        },
        .while_loop => |loop| {
            state.loop_nesting += 1;
            defer state.loop_nesting -= 1;

            const condition_type = try validateExpression(state, diagnostics, scope, loop.condition);
            try validateStatement(state, diagnostics, scope, loop.body.*);

            try performTypeCheck(diagnostics, stmt.location, TypeSet.from(.boolean), condition_type);
        },
        .for_loop => |loop| {
            state.loop_nesting += 1;
            defer state.loop_nesting -= 1;

            try scope.enter();

            scope.declare(loop.variable) catch |err| switch (err) {
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
            const conditional_type = try validateExpression(state, diagnostics, scope, conditional.condition);
            try validateStatement(state, diagnostics, scope, conditional.true_body.*);
            if (conditional.false_body) |body| {
                try validateStatement(state, diagnostics, scope, body.*);
            }

            try performTypeCheck(diagnostics, stmt.location, TypeSet.from(.boolean), conditional_type);
        },
        .declaration => |decl| {
            scope.declare(decl.variable) catch |err| switch (err) {
                error.AlreadyDeclared => try diagnostics.emit(.@"error", stmt.location, "Global variable {} is already declared!", .{decl.variable}),
                error.TooManyVariables => try emitTooManyVariables(diagnostics, stmt.location),
                else => |e| return e,
            };

            if (decl.initial_value) |init_val| {
                _ = try validateExpression(state, diagnostics, scope, init_val);
                // TODO: annotate variable type here
            }
        },
        .extern_variable => |name| {
            scope.declareExtern(name) catch |err| switch (err) {
                error.TooManyVariables => try emitTooManyVariables(diagnostics, stmt.location),
                else => |e| return e,
            };
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

pub fn validate(allocator: *std.mem.Allocator, diagnostics: *Diagnostics, program: ast.Program) !void {
    var global_scope = Scope.init(allocator, null, true);
    defer global_scope.deinit();

    for (program.root_script) |stmt| {
        var state = AnalysisState{
            .loop_nesting = 0,
        };

        try validateStatement(&state, diagnostics, &global_scope, stmt);
    }

    std.debug.assert(global_scope.return_point.items.len == 0);

    for (program.functions) |function, i| {
        for (program.functions[0..i]) |other_fn| {
            if (std.mem.eql(u8, function.name, other_fn.name)) {
                try diagnostics.emit(.@"error", function.location, "A function with the name {} was already declared!", .{function.name});
                break;
            }
        }

        var local_scope = Scope.init(allocator, &global_scope, false);
        defer local_scope.deinit();

        for (function.parameters) |param| {
            local_scope.declare(param) catch |err| switch (err) {
                error.AlreadyDeclared => try diagnostics.emit(.@"error", function.location, "A parameter {} is already declared!", .{param}),
                error.TooManyVariables => try emitTooManyVariables(diagnostics, function.location),
                else => |e| return e,
            };
        }

        var state = AnalysisState{
            .loop_nesting = 0,
        };
        try validateStatement(&state, diagnostics, &local_scope, function.body);
    }
}

test "validate" {
    _ = validate;
}
