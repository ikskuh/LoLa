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
};

const ValidationError = error{OutOfMemory};

fn emitTooManyVariables(diagnostics: *Diagnostics, location: Location) !void {
    try diagnostics.emit(.@"error", location, "Too many variables declared! The maximum allowed number of variables is 35535.", .{});
}

fn validateExpression(state: *AnalysisState, diagnostics: *Diagnostics, scope: *Scope, expr: ast.Expression) ValidationError!Type {
    // we're happy for now with expressions...
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

            _ = try validateExpression(state, diagnostics, scope, loop.condition);
            try validateStatement(state, diagnostics, scope, loop.body.*);
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

            _ = try validateExpression(state, diagnostics, scope, loop.source);
            try validateStatement(state, diagnostics, scope, loop.body.*);

            try scope.leave();
        },
        .if_statement => |conditional| {
            _ = try validateExpression(state, diagnostics, scope, conditional.condition);
            try validateStatement(state, diagnostics, scope, conditional.true_body.*);
            if (conditional.false_body) |body| {
                try validateStatement(state, diagnostics, scope, body.*);
            }
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
