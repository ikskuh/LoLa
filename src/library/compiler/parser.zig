const std = @import("std");

const lexer = @import("tokenizer.zig");
const ast = @import("ast.zig");
const diag = @import("diagnostics.zig");

/// Parses a sequence of tokens into an abstract syntax tree.
pub fn parse(
    allocator: *std.mem.Allocator,
    diagnostics: *diag.Diagnostics,
    sequence: []const lexer.Token,
) !ast.Program {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var root_script = std.ArrayList(ast.Statement).init(&arena.allocator);
    defer root_script.deinit();

    var functions = std.ArrayList(ast.Function).init(&arena.allocator);
    defer functions.deinit();

    const Parser = struct {
        const Self = @This();

        const Predicate = fn (lexer.Token) bool;

        const AcceptError = error{SyntaxError};
        const ParseError = std.mem.Allocator.Error || AcceptError;

        const SavedState = struct {
            index: usize,
        };

        allocator: *std.mem.Allocator,
        sequence: []const lexer.Token,
        index: usize = 0,

        /// Create a save state that allows rewinding the parser process.
        /// This should be used when a parsing function calls accept mulitple
        /// times and may emit a syntax error.
        /// The state should be restored in a errdefer.
        fn saveState(self: Self) SavedState {
            return SavedState{
                .index = self.index,
            };
        }

        /// Restores a previously created save state.
        fn restoreState(self: *Self, state: SavedState) void {
            self.index = state.index;
        }

        fn moveToHeap(self: *Self, value: anytype) !*@TypeOf(value) {
            const T = @TypeOf(value);
            std.debug.assert(@typeInfo(T) != .Pointer);
            const ptr = try self.allocator.create(T);
            ptr.* = value;
            return ptr;
        }

        fn is(comptime kind: lexer.TokenType) Predicate {
            return struct {
                fn pred(token: lexer.Token) bool {
                    return token.type == kind;
                }
            }.pred;
        }

        fn oneOf(comptime kinds: anytype) Predicate {
            return struct {
                fn pred(token: lexer.Token) bool {
                    return inline for (kinds) |k| {
                        if (token.type == k)
                            break true;
                    } else false;
                }
            }.pred;
        }

        fn peek(self: Self) AcceptError!lexer.Token {
            if (self.index >= self.sequence.len)
                return error.SyntaxError;
            return self.sequence[self.index];
        }

        fn accept(self: *Self, predicate: Predicate) AcceptError!lexer.Token {
            if (self.index >= self.sequence.len)
                return error.SyntaxError;
            const tok = self.sequence[self.index];
            if (predicate(tok)) {
                self.index += 1;
                return tok;
            } else {
                // std.debug.print("cannot accept {} here!\n", .{tok});
                return error.SyntaxError;
            }
        }

        fn acceptFunction(self: *Self) ParseError!ast.Function {
            const state = self.saveState();
            errdefer self.restoreState(state);

            const initial_pos = try self.accept(is(.function));

            const name = try self.accept(is(.identifier));

            _ = try self.accept(is(.@"("));

            var args = std.ArrayList([]const u8).init(self.allocator);
            defer args.deinit();

            while (true) {
                const arg_or_end = try self.accept(oneOf(.{ .identifier, .@")" }));
                switch (arg_or_end.type) {
                    .@")" => break,
                    .identifier => {
                        try args.append(arg_or_end.text);
                        const delimit = try self.accept(oneOf(.{ .@",", .@")" }));
                        if (delimit.type == .@")")
                            break;
                    },
                    else => unreachable,
                }
            }

            const block = try self.acceptBlock();

            return ast.Function{
                .location = initial_pos.location,
                .name = name.text,
                .parameters = args.toOwnedSlice(),
                .body = block,
            };
        }

        fn acceptBlock(self: *Self) ParseError!ast.Statement {
            const state = self.saveState();
            errdefer self.restoreState(state);

            const begin = try self.accept(is(.@"{"));

            var body = std.ArrayList(ast.Statement).init(self.allocator);
            defer body.deinit();

            while (true) {
                const stmt = self.acceptStatement() catch break;
                try body.append(stmt);
            }
            const end = try self.accept(is(.@"}"));

            return ast.Statement{
                .location = begin.location,
                .type = .{
                    .block = body.toOwnedSlice(),
                },
            };
        }

        fn acceptStatement(self: *Self) ParseError!ast.Statement {
            const state = self.saveState();
            errdefer self.restoreState(state);

            const start = try self.peek();

            switch (start.type) {
                .@";" => {
                    _ = try self.accept(is(.@";"));
                    return ast.Statement{
                        .location = start.location,
                        .type = .empty,
                    };
                },
                .@"break" => {
                    _ = try self.accept(is(.@"break"));
                    _ = try self.accept(is(.@";"));
                    return ast.Statement{
                        .location = start.location,
                        .type = .@"break",
                    };
                },
                .@"continue" => {
                    _ = try self.accept(is(.@"continue"));
                    _ = try self.accept(is(.@";"));
                    return ast.Statement{
                        .location = start.location,
                        .type = .@"continue",
                    };
                },
                .@"{" => {
                    return try self.acceptBlock();
                },
                .@"while" => {
                    _ = try self.accept(is(.@"while"));
                    _ = try self.accept(is(.@"("));
                    const condition = try self.acceptExpression();
                    _ = try self.accept(is(.@")"));

                    const body = try self.acceptBlock();

                    return ast.Statement{
                        .location = start.location,
                        .type = .{
                            .while_loop = .{
                                .condition = condition,
                                .body = try self.moveToHeap(body),
                            },
                        },
                    };
                },
                .@"if" => {
                    _ = try self.accept(is(.@"if"));
                    _ = try self.accept(is(.@"("));

                    const condition = try self.acceptExpression();

                    _ = try self.accept(is(.@")"));

                    const true_body = try self.acceptStatement();

                    if (self.accept(is(.@"else"))) |_| {
                        const false_body = try self.acceptStatement();
                        return ast.Statement{
                            .location = start.location,
                            .type = .{
                                .if_statement = .{
                                    .condition = condition,
                                    .true_body = try self.moveToHeap(true_body),
                                    .false_body = try self.moveToHeap(false_body),
                                },
                            },
                        };
                    } else |_| {
                        return ast.Statement{
                            .location = start.location,
                            .type = .{
                                .if_statement = .{
                                    .condition = condition,
                                    .true_body = try self.moveToHeap(true_body),
                                    .false_body = null,
                                },
                            },
                        };
                    }
                },
                .@"for" => {
                    _ = try self.accept(is(.@"for"));
                    _ = try self.accept(is(.@"("));
                    const name = try self.accept(is(.identifier));

                    _ = try self.accept(is(.in));

                    const source = try self.acceptExpression();

                    _ = try self.accept(is(.@")"));

                    const body = try self.acceptBlock();

                    return ast.Statement{
                        .location = start.location,
                        .type = .{
                            .for_loop = .{
                                .variable = name.text,
                                .source = source,
                                .body = try self.moveToHeap(body),
                            },
                        },
                    };
                },

                .@"return" => {
                    _ = try self.accept(is(.@"return"));

                    if (self.accept(is(.@";"))) |_| {
                        return ast.Statement{
                            .location = start.location,
                            .type = .return_void,
                        };
                    } else |_| {
                        const value = try self.acceptExpression();

                        _ = try self.accept(is(.@";"));

                        return ast.Statement{
                            .location = start.location,
                            .type = .{
                                .return_expr = value,
                            },
                        };
                    }
                },

                .@"extern" => {
                    _ = try self.accept(is(.@"extern"));
                    const name = try self.accept(is(.identifier));
                    _ = try self.accept(is(.@";"));

                    return ast.Statement{
                        .location = start.location.merge(name.location),
                        .type = .{
                            .extern_variable = name.text,
                        },
                    };
                },

                .@"var" => {
                    _ = try self.accept(is(.@"var"));
                    const name = try self.accept(is(.identifier));
                    const decider = try self.accept(oneOf(.{ .@";", .@"=" }));

                    var stmt = ast.Statement{
                        .location = start.location.merge(name.location),
                        .type = .{
                            .declaration = .{
                                .variable = name.text,
                                .initial_value = null,
                            },
                        },
                    };

                    if (decider.type == .@"=") {
                        const value = try self.acceptExpression();

                        _ = try self.accept(is(.@";"));

                        stmt.type.declaration.initial_value = value;
                    }

                    return stmt;
                },

                else => {
                    const expr = try self.acceptExpression();

                    if ((expr.type == .function_call) or (expr.type == .method_call)) {
                        _ = try self.accept(is(.@";"));

                        return ast.Statement{
                            .location = expr.location,
                            .type = .{
                                .discard_value = expr,
                            },
                        };
                    } else {
                        _ = try self.accept(is(.@"="));

                        const value = try self.acceptExpression();

                        _ = try self.accept(is(.@";"));

                        return ast.Statement{
                            .location = expr.location,
                            .type = .{
                                .assignment = .{
                                    .target = expr,
                                    .value = value,
                                },
                            },
                        };
                    }
                },
            }
        }

        fn acceptExpression(self: *Self) ParseError!ast.Expression {
            return try self.acceptLogicCombinatorExpression();
        }

        fn acceptLogicCombinatorExpression(self: *Self) ParseError!ast.Expression {
            var expr = try self.acceptComparisonExpression();
            while (true) {
                var and_or = self.accept(oneOf(.{ .@"and", .@"or" })) catch break;
                var rhs = try self.acceptComparisonExpression();

                expr = ast.Expression{
                    .location = expr.location.merge(and_or.location).merge(rhs.location),
                    .type = .{
                        .binary_operator = .{
                            .operator = switch (and_or.type) {
                                .@"and" => .boolean_and,
                                .@"or" => .boolean_or,
                                else => unreachable,
                            },
                            .lhs = try self.moveToHeap(expr),
                            .rhs = try self.moveToHeap(rhs),
                        },
                    },
                };
            }
            return expr;
        }

        fn acceptComparisonExpression(self: *Self) ParseError!ast.Expression {
            var expr = try self.acceptSumExpression();
            while (true) {
                var and_or = self.accept(oneOf(.{
                    .@"<=",
                    .@">=",
                    .@">",
                    .@"<",
                    .@"==",
                    .@"!=",
                })) catch break;
                var rhs = try self.acceptSumExpression();

                expr = ast.Expression{
                    .location = expr.location.merge(and_or.location).merge(rhs.location),
                    .type = .{
                        .binary_operator = .{
                            .operator = switch (and_or.type) {
                                .@"<=" => .less_or_equal_than,
                                .@">=" => .greater_or_equal_than,
                                .@">" => .greater_than,
                                .@"<" => .less_than,
                                .@"==" => .equal,
                                .@"!=" => .different,
                                else => unreachable,
                            },
                            .lhs = try self.moveToHeap(expr),
                            .rhs = try self.moveToHeap(rhs),
                        },
                    },
                };
            }
            return expr;
        }

        fn acceptSumExpression(self: *Self) ParseError!ast.Expression {
            var expr = try self.acceptMulExpression();
            while (true) {
                var and_or = self.accept(oneOf(.{
                    .@"+",
                    .@"-",
                })) catch break;
                var rhs = try self.acceptMulExpression();

                expr = ast.Expression{
                    .location = expr.location.merge(and_or.location).merge(rhs.location),
                    .type = .{
                        .binary_operator = .{
                            .operator = switch (and_or.type) {
                                .@"+" => .add,
                                .@"-" => .subtract,
                                else => unreachable,
                            },
                            .lhs = try self.moveToHeap(expr),
                            .rhs = try self.moveToHeap(rhs),
                        },
                    },
                };
            }
            return expr;
        }

        fn acceptMulExpression(self: *Self) ParseError!ast.Expression {
            var expr = try self.acceptUnaryPrefixOperatorExpression();
            while (true) {
                var and_or = self.accept(oneOf(.{
                    .@"*",
                    .@"/",
                    .@"%",
                })) catch break;
                var rhs = try self.acceptUnaryPrefixOperatorExpression();

                expr = ast.Expression{
                    .location = expr.location.merge(and_or.location).merge(rhs.location),
                    .type = .{
                        .binary_operator = .{
                            .operator = switch (and_or.type) {
                                .@"*" => .multiply,
                                .@"/" => .divide,
                                .@"%" => .modulus,
                                else => unreachable,
                            },
                            .lhs = try self.moveToHeap(expr),
                            .rhs = try self.moveToHeap(rhs),
                        },
                    },
                };
            }
            return expr;
        }

        fn acceptUnaryPrefixOperatorExpression(self: *Self) ParseError!ast.Expression {
            if (self.accept(oneOf(.{ .@"not", .@"-" }))) |prefix| {
                // this must directly recurse as we can write `not not x`
                const value = try self.acceptUnaryPrefixOperatorExpression();
                return ast.Expression{
                    .location = prefix.location.merge(value.location),
                    .type = .{
                        .unary_operator = .{
                            .operator = switch (prefix.type) {
                                .@"not" => .boolean_not,
                                .@"-" => .boolean_not,
                                else => unreachable,
                            },
                            .value = try self.moveToHeap(value),
                        },
                    },
                };
            } else |_| {
                return try self.acceptIndexingExpression();
            }
        }

        fn acceptIndexingExpression(self: *Self) ParseError!ast.Expression {
            const value = try self.acceptValueExpression();

            // TODO: This is broken right now, it prevents use
            // of `a[x][y]`.

            if (self.accept(is(.@"["))) |_| {
                const index = try self.acceptValueExpression();

                _ = try self.accept(is(.@"]"));

                return ast.Expression{
                    .location = value.location.merge(index.location),
                    .type = .{
                        .array_indexer = .{
                            .value = try self.moveToHeap(value),
                            .index = try self.moveToHeap(index),
                        },
                    },
                };
            } else |_| {
                return value;
            }
        }

        fn acceptValueExpression(self: *Self) ParseError!ast.Expression {
            const token = try self.accept(oneOf(.{
                .@"(",
                .@"[",
                .number_literal,
                .string_literal,
                .identifier,
            }));
            switch (token.type) {
                .@"(" => {
                    const value = try self.acceptExpression();
                    _ = try self.accept(is(.@")"));
                    return value;
                },
                .@"[" => @panic("TODO: Implement array literals"),
                .number_literal => {
                    const val = std.fmt.parseFloat(f64, token.text) catch return error.SyntaxError;
                    return ast.Expression{
                        .location = token.location,
                        .type = .{
                            .number_literal = val,
                        },
                    };
                },
                .string_literal => {
                    // TODO: Escape string here!
                    std.debug.print("TODO: Apply string escapes here!\n", .{});
                    return ast.Expression{
                        .location = token.location,
                        .type = .{
                            .string_literal = token.text,
                        },
                    };
                },
                .identifier => return ast.Expression{
                    .location = token.location,
                    .type = .{
                        .variable_expr = token.text,
                    },
                },
                else => unreachable,
            }
        }
    };

    var parser = Parser{
        .allocator = &arena.allocator,
        .sequence = sequence,
    };

    while (parser.index < parser.sequence.len) {
        const state = parser.saveState();

        // look-ahead one token and try accepting a "function" keyword,
        // use that to select between parsing a function or a statement.
        if (parser.accept(Parser.is(.function))) |_| {
            // we need to unaccept the function token
            parser.restoreState(state);

            const fun = try parser.acceptFunction();
            try functions.append(fun);
        } else |_| {
            // no need to unaccept here as we didn't accept in the first place
            const stmt = try parser.acceptStatement();
            try root_script.append(stmt);
        }
    }

    return ast.Program{
        .arena = arena,
        .root_script = root_script.toOwnedSlice(),
        .functions = functions.toOwnedSlice(),
    };
}

fn testTokenize(str: []const u8) ![]lexer.Token {
    var result = std.ArrayList(lexer.Token).init(std.testing.allocator);
    var tokenizer = lexer.Tokenizer.init("testsrc", str);

    while (true) {
        switch (tokenizer.next()) {
            .end_of_file => return result.toOwnedSlice(),
            .invalid_sequence => unreachable, // we don't do that here
            .token => |token| try result.append(token),
        }
    }
}

test "empty file parsing" {
    var diagnostics = diag.Diagnostics.init(std.testing.allocator);
    defer diagnostics.deinit();

    var pgm = try parse(std.testing.allocator, &diagnostics, &[_]lexer.Token{});
    defer pgm.deinit();

    // assert that an empty file results in a empty AST
    std.testing.expectEqual(@as(usize, 0), pgm.root_script.len);
    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);

    // assert that we didn't encounter syntax errors
    std.testing.expectEqual(@as(usize, 0), diagnostics.messages.items.len);
}

fn parseTest(string: []const u8) !ast.Program {
    const seq = try testTokenize(string);
    defer std.testing.allocator.free(seq);

    var diagnostics = diag.Diagnostics.init(std.testing.allocator);
    defer diagnostics.deinit();

    return try parse(std.testing.allocator, &diagnostics, seq);
}

test "parse single top level statement" {
    // test with the simplest of all statements:
    // the empty one
    var pgm = try parseTest(";");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.empty, pgm.root_script[0].type);
}

test "parse single empty function" {
    // 0 params
    {
        var pgm = try parseTest("function empty(){}");
        defer pgm.deinit();

        std.testing.expectEqual(@as(usize, 1), pgm.functions.len);
        std.testing.expectEqual(@as(usize, 0), pgm.root_script.len);

        const fun = pgm.functions[0];

        std.testing.expectEqualStrings("empty", fun.name);
        std.testing.expectEqual(ast.Statement.Type.block, fun.body.type);
        std.testing.expectEqual(@as(usize, 0), fun.body.type.block.len);
        std.testing.expectEqual(@as(usize, 0), fun.parameters.len);
    }

    // 1 param
    {
        var pgm = try parseTest("function empty(p0){}");
        defer pgm.deinit();

        std.testing.expectEqual(@as(usize, 1), pgm.functions.len);
        std.testing.expectEqual(@as(usize, 0), pgm.root_script.len);

        const fun = pgm.functions[0];

        std.testing.expectEqualStrings("empty", fun.name);
        std.testing.expectEqual(ast.Statement.Type.block, fun.body.type);
        std.testing.expectEqual(@as(usize, 0), fun.body.type.block.len);
        std.testing.expectEqual(@as(usize, 1), fun.parameters.len);
        std.testing.expectEqualStrings("p0", fun.parameters[0]);
    }

    // 3 param
    {
        var pgm = try parseTest("function empty(p0,p1,p2){}");
        defer pgm.deinit();

        std.testing.expectEqual(@as(usize, 1), pgm.functions.len);
        std.testing.expectEqual(@as(usize, 0), pgm.root_script.len);

        const fun = pgm.functions[0];

        std.testing.expectEqualStrings("empty", fun.name);
        std.testing.expectEqual(ast.Statement.Type.block, fun.body.type);
        std.testing.expectEqual(@as(usize, 0), fun.body.type.block.len);
        std.testing.expectEqual(@as(usize, 3), fun.parameters.len);
        std.testing.expectEqualStrings("p0", fun.parameters[0]);
        std.testing.expectEqualStrings("p1", fun.parameters[1]);
        std.testing.expectEqualStrings("p2", fun.parameters[2]);
    }
}

test "parse multiple top level statements" {
    // test with the simplest of all statements:
    // the empty one
    var pgm = try parseTest(";;;");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 3), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.empty, pgm.root_script[0].type);
    std.testing.expectEqual(ast.Statement.Type.empty, pgm.root_script[1].type);
    std.testing.expectEqual(ast.Statement.Type.empty, pgm.root_script[2].type);
}

test "parse mixed function and top level statement" {
    var pgm = try parseTest(";function n(){};");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 1), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 2), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.empty, pgm.root_script[0].type);
    std.testing.expectEqual(ast.Statement.Type.empty, pgm.root_script[1].type);

    const fun = pgm.functions[0];

    std.testing.expectEqualStrings("n", fun.name);
    std.testing.expectEqual(ast.Statement.Type.block, fun.body.type);
    std.testing.expectEqual(@as(usize, 0), fun.body.type.block.len);
    std.testing.expectEqual(@as(usize, 0), fun.parameters.len);
}

test "nested blocks" {
    var pgm = try parseTest(
        \\{ }
        \\{
        \\  { ; } 
        \\  { ; ; }
        \\  ;
        \\}
        \\{ }
    );
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 3), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.block, pgm.root_script[0].type);
    std.testing.expectEqual(ast.Statement.Type.block, pgm.root_script[1].type);
    std.testing.expectEqual(ast.Statement.Type.block, pgm.root_script[2].type);

    std.testing.expectEqual(@as(usize, 0), pgm.root_script[0].type.block.len);
    std.testing.expectEqual(@as(usize, 3), pgm.root_script[1].type.block.len);
    std.testing.expectEqual(@as(usize, 0), pgm.root_script[2].type.block.len);

    std.testing.expectEqual(ast.Statement.Type.block, pgm.root_script[1].type.block[0].type);
    std.testing.expectEqual(ast.Statement.Type.block, pgm.root_script[1].type.block[1].type);
    std.testing.expectEqual(ast.Statement.Type.empty, pgm.root_script[1].type.block[2].type);

    std.testing.expectEqual(@as(usize, 1), pgm.root_script[1].type.block[0].type.block.len);
    std.testing.expectEqual(@as(usize, 2), pgm.root_script[1].type.block[1].type.block.len);

    std.testing.expectEqual(ast.Statement.Type.empty, pgm.root_script[1].type.block[1].type.block[0].type);
    std.testing.expectEqual(ast.Statement.Type.empty, pgm.root_script[1].type.block[1].type.block[0].type);
}

test "nested blocks in functions" {
    var pgm = try parseTest(
        \\function foo() {
        \\  { }
        \\  {
        \\    { ; } 
        \\    { ; ; }
        \\    ;
        \\  }
        \\  { }
        \\}
    );
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 1), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 0), pgm.root_script.len);

    const fun = pgm.functions[0];

    std.testing.expectEqual(ast.Statement.Type.block, fun.body.type);

    const items = fun.body.type.block;

    std.testing.expectEqual(ast.Statement.Type.block, items[0].type);
    std.testing.expectEqual(ast.Statement.Type.block, items[1].type);
    std.testing.expectEqual(ast.Statement.Type.block, items[2].type);

    std.testing.expectEqual(@as(usize, 0), items[0].type.block.len);
    std.testing.expectEqual(@as(usize, 3), items[1].type.block.len);
    std.testing.expectEqual(@as(usize, 0), items[2].type.block.len);

    std.testing.expectEqual(ast.Statement.Type.block, items[1].type.block[0].type);
    std.testing.expectEqual(ast.Statement.Type.block, items[1].type.block[1].type);
    std.testing.expectEqual(ast.Statement.Type.empty, items[1].type.block[2].type);

    std.testing.expectEqual(@as(usize, 1), items[1].type.block[0].type.block.len);
    std.testing.expectEqual(@as(usize, 2), items[1].type.block[1].type.block.len);

    std.testing.expectEqual(ast.Statement.Type.empty, items[1].type.block[1].type.block[0].type);
    std.testing.expectEqual(ast.Statement.Type.empty, items[1].type.block[1].type.block[0].type);
}

test "parsing break" {
    var pgm = try parseTest("break;");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.@"break", pgm.root_script[0].type);
}

test "parsing continue" {
    var pgm = try parseTest("continue;");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.@"continue", pgm.root_script[0].type);
}

test "parsing while" {
    var pgm = try parseTest("while(1) { }");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.while_loop, pgm.root_script[0].type);
    std.testing.expectEqual(ast.Statement.Type.block, pgm.root_script[0].type.while_loop.body.type);
    std.testing.expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.while_loop.condition.type);
}

test "parsing for" {
    var pgm = try parseTest("for(name in 1) { }");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.for_loop, pgm.root_script[0].type);
    std.testing.expectEqualStrings("name", pgm.root_script[0].type.for_loop.variable);
    std.testing.expectEqual(ast.Statement.Type.block, pgm.root_script[0].type.for_loop.body.type);
    std.testing.expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.for_loop.source.type);
}

test "parsing single if" {
    var pgm = try parseTest("if(1) { }");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.if_statement, pgm.root_script[0].type);
    std.testing.expectEqual(ast.Statement.Type.block, pgm.root_script[0].type.if_statement.true_body.type);
    std.testing.expectEqual(@as(?*ast.Statement, null), pgm.root_script[0].type.if_statement.false_body);
    std.testing.expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.if_statement.condition.type);
}

test "parsing if-else" {
    var pgm = try parseTest("if(1) { } else ;");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.if_statement, pgm.root_script[0].type);
    std.testing.expectEqual(ast.Statement.Type.block, pgm.root_script[0].type.if_statement.true_body.type);
    std.testing.expectEqual(ast.Statement.Type.empty, pgm.root_script[0].type.if_statement.false_body.?.type);
    std.testing.expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.if_statement.condition.type);
}

test "parsing return (void)" {
    var pgm = try parseTest("return;");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.return_void, pgm.root_script[0].type);
}

test "parsing return (value)" {
    var pgm = try parseTest("return 1;");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.return_expr, pgm.root_script[0].type);
    std.testing.expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.return_expr.type);
}

test "parsing extern declaration" {
    var pgm = try parseTest("extern name;");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.extern_variable, pgm.root_script[0].type);
    std.testing.expectEqualStrings("name", pgm.root_script[0].type.extern_variable);
}

test "parsing declaration (no value)" {
    var pgm = try parseTest("var name;");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.declaration, pgm.root_script[0].type);
    std.testing.expectEqualStrings("name", pgm.root_script[0].type.declaration.variable);
    std.testing.expectEqual(@as(?ast.Expression, null), pgm.root_script[0].type.declaration.initial_value);
}

test "parsing declaration (initial value)" {
    var pgm = try parseTest("var name = 1;");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.declaration, pgm.root_script[0].type);
    std.testing.expectEqualStrings("name", pgm.root_script[0].type.declaration.variable);
    std.testing.expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.declaration.initial_value.?.type);
}

test "parsing assignment" {
    var pgm = try parseTest("1 = 1;");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.assignment, pgm.root_script[0].type);
    std.testing.expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.target.type);
    std.testing.expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.value.type);
}

test "parsing operator-assignment" {
    var pgm = try parseTest("1 = 1;");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.Type.assignment, pgm.root_script[0].type);
    std.testing.expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.target.type);
    std.testing.expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.value.type);
}

/// Parse a program with `1 = $(EXPR)`, will return `$(EXPR)`
fn getTestExpr(pgm: ast.Program) ast.Expression {
    std.testing.expectEqual(@as(usize, 0), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 1), pgm.root_script.len);
    std.testing.expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.target.type);
    return pgm.root_script[0].type.assignment.value;
}

test "number literal" {
    var pgm = try parseTest("1 = 1;");
    defer pgm.deinit();

    const expr = getTestExpr(pgm);

    std.testing.expectEqual(ast.Expression.Type.number_literal, expr.type);
    std.testing.expectWithinEpsilon(@as(f64, 1), expr.type.number_literal, 0.000001);
}

test "addition literal" {
    var pgm = try parseTest("1 = 1 + 1;");
    defer pgm.deinit();

    const expr = getTestExpr(pgm);

    std.testing.expectEqual(ast.Expression.Type.binary_operator, expr.type);
    std.testing.expectEqual(ast.BinaryOperator.add, expr.type.binary_operator.operator);
}

test "mutiplication literal" {
    var pgm = try parseTest("1 = 1 * 1;");
    defer pgm.deinit();

    const expr = getTestExpr(pgm);

    std.testing.expectEqual(ast.Expression.Type.binary_operator, expr.type);
    std.testing.expectEqual(ast.BinaryOperator.multiply, expr.type.binary_operator.operator);
}

test "operator precedence literal" {
    var pgm = try parseTest("1 = 1 + 1 * 1;");
    defer pgm.deinit();

    const expr = getTestExpr(pgm);

    std.testing.expectEqual(ast.Expression.Type.binary_operator, expr.type);
    std.testing.expectEqual(ast.BinaryOperator.add, expr.type.binary_operator.operator);

    std.testing.expectEqual(ast.Expression.Type.binary_operator, expr.type.binary_operator.rhs.type);
    std.testing.expectEqual(ast.BinaryOperator.multiply, expr.type.binary_operator.rhs.type.binary_operator.operator);
}

test "full suite parsing" {
    return error.SkipZigTest;

    // TODO: Reinclude this test when the parser is done.
    // const seq = try testTokenize(@embedFile("../../test/compiler.lola"));
    // defer std.testing.allocator.free(seq);

    // var diagnostics = diag.Diagnostics.init(std.testing.allocator);
    // defer diagnostics.deinit();

    // var pgm = try parse(std.testing.allocator, &diagnostics, seq);
    // defer pgm.deinit();

    // // assert that we don't have an empty AST
    // std.testing.expect(pgm.root_script.len > 0);
    // std.testing.expect(pgm.functions.len > 0);

    // // assert that we didn't encounter syntax errors
    // std.testing.expectEqual(@as(usize, 0), diagnostics.messages.items.len);
}