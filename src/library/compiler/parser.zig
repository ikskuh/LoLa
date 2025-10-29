const std = @import("std");

const lexer = @import("tokenizer.zig");
const ast = @import("ast.zig");
const diag = @import("diagnostics.zig");

const Location = @import("location.zig").Location;
const EscapedStringIterator = @import("string-escaping.zig").EscapedStringIterator;

/// Parses a sequence of tokens into an abstract syntax tree.
/// Returns either a successfully parsed tree or puts all found
/// syntax errors into `diagnostics`.
pub fn parse(
    allocator: std.mem.Allocator,
    diagnostics: *diag.Diagnostics,
    sequence: []const lexer.Token,
) !ast.Program {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();

    var root_script = std.ArrayList(ast.Statement).empty;
    defer root_script.deinit(alloc);

    var functions = std.ArrayList(ast.Function).empty;
    defer functions.deinit(alloc);

    const Parser = struct {
        const Self = @This();

        const Predicate = *const (fn (lexer.Token) bool);

        const AcceptError = error{SyntaxError};
        const ParseError = std.mem.Allocator.Error || AcceptError;

        const SavedState = struct {
            index: usize,
        };

        allocator: std.mem.Allocator,
        sequence: []const lexer.Token,
        index: usize = 0,
        diagnostics: *diag.Diagnostics,

        fn emitDiagnostics(self: *Self, comptime fmt: []const u8, args: anytype) error{ OutOfMemory, SyntaxError } {
            try self.diagnostics.emit(.@"error", self.getCurrentLocation(), fmt, args);
            return error.SyntaxError;
        }

        fn getCurrentLocation(self: Self) Location {
            return self.sequence[self.index].location;
        }

        /// Applies all known string escape codes
        fn escapeString(self: Self, input: []const u8) ![]u8 {
            var iterator = EscapedStringIterator.init(input);

            var len: usize = 0;
            while (try iterator.next()) |_| {
                len += 1;
            }

            iterator = EscapedStringIterator.init(input);

            const result = try self.allocator.alloc(u8, len);
            var i: usize = 0;
            while (iterator.next() catch unreachable) |c| {
                result[i] = c;
                i += 1;
            }
            std.debug.assert(i == len);

            return result;
        }

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
            std.debug.assert(@typeInfo(T) != .pointer);
            const ptr = try self.allocator.create(T);
            ptr.* = value;

            std.debug.assert(std.meta.eql(ptr.*, value));

            return ptr;
        }

        fn any(token: lexer.Token) bool {
            _ = token;
            return true;
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

            var args = std.ArrayList([]const u8).empty;

            while (true) {
                const arg_or_end = try self.accept(oneOf(.{ .identifier, .@")" }));
                switch (arg_or_end.type) {
                    .@")" => break,
                    .identifier => {
                        try args.append(self.allocator, arg_or_end.text);
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
                .parameters = try args.toOwnedSlice(self.allocator),
                .body = block,
            };
        }

        fn acceptBlock(self: *Self) ParseError!ast.Statement {
            const state = self.saveState();
            errdefer self.restoreState(state);

            const begin = try self.accept(is(.@"{"));

            var body = std.ArrayList(ast.Statement).empty;

            while (true) {
                const stmt = self.acceptStatement() catch break;
                try body.append(self.allocator, stmt);
            }
            _ = try self.accept(is(.@"}"));

            return ast.Statement{
                .location = begin.location,
                .type = .{
                    .block = try body.toOwnedSlice(self.allocator),
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

                .@"var", .@"const" => {
                    const decl_type = try self.accept(oneOf(.{ .@"var", .@"const" }));

                    const name = try self.accept(is(.identifier));
                    const decider = try self.accept(oneOf(.{ .@";", .@"=" }));

                    var stmt = ast.Statement{
                        .location = start.location.merge(name.location),
                        .type = .{
                            .declaration = .{
                                .variable = name.text,
                                .initial_value = null,
                                .is_const = (decl_type.type == .@"const"),
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
                        const mode = try self.accept(oneOf(.{
                            .@"=",
                            .@"+=",
                            .@"-=",
                            .@"*=",
                            .@"/=",
                            .@"%=",
                        }));

                        const value = try self.acceptExpression();

                        _ = try self.accept(is(.@";"));

                        return switch (mode.type) {
                            .@"+=", .@"-=", .@"*=", .@"/=", .@"%=" => ast.Statement{
                                .location = expr.location,
                                .type = .{
                                    .assignment = .{
                                        .target = expr,
                                        .value = ast.Expression{
                                            .location = expr.location,
                                            .type = .{
                                                .binary_operator = .{
                                                    .operator = switch (mode.type) {
                                                        .@"+=" => .add,
                                                        .@"-=" => .subtract,
                                                        .@"*=" => .multiply,
                                                        .@"/=" => .divide,
                                                        .@"%=" => .modulus,
                                                        else => unreachable,
                                                    },
                                                    .lhs = try self.moveToHeap(expr),
                                                    .rhs = try self.moveToHeap(value),
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                            .@"=" => ast.Statement{
                                .location = expr.location,
                                .type = .{
                                    .assignment = .{
                                        .target = expr,
                                        .value = value,
                                    },
                                },
                            },
                            else => unreachable,
                        };
                    }
                },
            }
        }

        fn acceptExpression(self: *Self) ParseError!ast.Expression {
            const state = self.saveState();
            errdefer self.restoreState(state);

            return try self.acceptLogicCombinatorExpression();
        }

        fn acceptLogicCombinatorExpression(self: *Self) ParseError!ast.Expression {
            const state = self.saveState();
            errdefer self.restoreState(state);

            var expr = try self.acceptComparisonExpression();
            while (true) {
                const and_or = self.accept(oneOf(.{ .@"and", .@"or" })) catch break;
                const rhs = try self.acceptComparisonExpression();

                const new_expr = ast.Expression{
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
                expr = new_expr;
            }
            return expr;
        }

        fn acceptComparisonExpression(self: *Self) ParseError!ast.Expression {
            const state = self.saveState();
            errdefer self.restoreState(state);

            var expr = try self.acceptSumExpression();
            while (true) {
                const and_or = self.accept(oneOf(.{
                    .@"<=",
                    .@">=",
                    .@">",
                    .@"<",
                    .@"==",
                    .@"!=",
                })) catch break;
                const rhs = try self.acceptSumExpression();

                const new_expr = ast.Expression{
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
                expr = new_expr;
            }
            return expr;
        }

        fn acceptSumExpression(self: *Self) ParseError!ast.Expression {
            const state = self.saveState();
            errdefer self.restoreState(state);

            var expr = try self.acceptMulExpression();
            while (true) {
                const and_or = self.accept(oneOf(.{
                    .@"+",
                    .@"-",
                })) catch break;
                const rhs = try self.acceptMulExpression();

                const new_expr = ast.Expression{
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
                expr = new_expr;
            }
            return expr;
        }

        fn acceptMulExpression(self: *Self) ParseError!ast.Expression {
            const state = self.saveState();
            errdefer self.restoreState(state);

            var expr = try self.acceptUnaryPrefixOperatorExpression();
            while (true) {
                const and_or = self.accept(oneOf(.{
                    .@"*",
                    .@"/",
                    .@"%",
                })) catch break;
                const rhs = try self.acceptUnaryPrefixOperatorExpression();

                const new_expr = ast.Expression{
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
                expr = new_expr;
            }
            return expr;
        }

        fn acceptUnaryPrefixOperatorExpression(self: *Self) ParseError!ast.Expression {
            const state = self.saveState();
            errdefer self.restoreState(state);

            if (self.accept(oneOf(.{ .not, .@"-" }))) |prefix| {
                // this must directly recurse as we can write `not not x`
                const value = try self.acceptUnaryPrefixOperatorExpression();
                return ast.Expression{
                    .location = prefix.location.merge(value.location),
                    .type = .{
                        .unary_operator = .{
                            .operator = switch (prefix.type) {
                                .not => .boolean_not,
                                .@"-" => .negate,
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
            const state = self.saveState();
            errdefer self.restoreState(state);

            var value = try self.acceptCallExpression();

            while (self.accept(is(.@"["))) |_| {
                const index = try self.acceptExpression();

                _ = try self.accept(is(.@"]"));

                const new_value = ast.Expression{
                    .location = value.location.merge(index.location),
                    .type = .{
                        .array_indexer = .{
                            .value = try self.moveToHeap(value),
                            .index = try self.moveToHeap(index),
                        },
                    },
                };
                value = new_value;
            } else |_| {}

            return value;
        }

        fn acceptCallExpression(self: *Self) ParseError!ast.Expression {
            const state = self.saveState();
            errdefer self.restoreState(state);

            var value = try self.acceptValueExpression();

            while (self.accept(oneOf(.{ .@"(", .@"." }))) |sym| {
                const new_value = switch (sym.type) {
                    // call
                    .@"(" => blk: {
                        var args = std.ArrayList(ast.Expression).empty;
                        defer args.deinit(self.allocator);

                        var loc = value.location;

                        if (self.accept(is(.@")"))) |_| {
                            // this is the end of the argument list
                        } else |_| {
                            while (true) {
                                const arg = try self.acceptExpression();
                                try args.append(self.allocator, arg);
                                const terminator = try self.accept(oneOf(.{ .@")", .@"," }));
                                loc = terminator.location.merge(loc);
                                if (terminator.type == .@")")
                                    break;
                            }
                        }

                        break :blk ast.Expression{
                            .location = loc,
                            .type = .{
                                .function_call = .{
                                    .function = try self.moveToHeap(value),
                                    .arguments = try args.toOwnedSlice(self.allocator),
                                },
                            },
                        };
                    },

                    // method call
                    .@"." => blk: {
                        const method_name = try self.accept(is(.identifier));

                        _ = try self.accept(is(.@"("));

                        var args = std.ArrayList(ast.Expression).empty;
                        defer args.deinit(self.allocator);

                        var loc = value.location;

                        if (self.accept(is(.@")"))) |_| {
                            // this is the end of the argument list
                        } else |_| {
                            while (true) {
                                const arg = try self.acceptExpression();
                                try args.append(self.allocator, arg);
                                const terminator = try self.accept(oneOf(.{ .@")", .@"," }));
                                loc = terminator.location.merge(loc);
                                if (terminator.type == .@")")
                                    break;
                            }
                        }

                        break :blk ast.Expression{
                            .location = loc,
                            .type = .{
                                .method_call = .{
                                    .object = try self.moveToHeap(value),
                                    .name = method_name.text,
                                    .arguments = try args.toOwnedSlice(self.allocator),
                                },
                            },
                        };
                    },

                    else => unreachable,
                };
                value = new_value;
            } else |_| {}

            return value;
        }

        fn acceptValueExpression(self: *Self) ParseError!ast.Expression {
            const state = self.saveState();
            errdefer self.restoreState(state);

            const token = try self.accept(oneOf(.{
                .@"(",
                .@"[",
                .number_literal,
                .string_literal,
                .character_literal,
                .identifier,
            }));
            switch (token.type) {
                .@"(" => {
                    const value = try self.acceptExpression();
                    _ = try self.accept(is(.@")"));
                    return value;
                },
                .@"[" => {
                    var array = std.ArrayList(ast.Expression).empty;
                    defer array.deinit(self.allocator);

                    while (true) {
                        if (self.accept(is(.@"]"))) |_| {
                            break;
                        } else |_| {
                            const item = try self.acceptExpression();

                            try array.append(self.allocator, item);

                            const delimit = try self.accept(oneOf(.{ .@",", .@"]" }));
                            if (delimit.type == .@"]")
                                break;
                        }
                    }
                    return ast.Expression{
                        .location = token.location,
                        .type = .{
                            .array_literal = try array.toOwnedSlice(self.allocator),
                        },
                    };
                },
                .number_literal => {
                    const val = if (std.mem.startsWith(u8, token.text, "0x"))
                        @as(f64, @floatFromInt(std.fmt.parseInt(i54, token.text[2..], 16) catch return self.emitDiagnostics("`{s}` is not a valid hexadecimal number!", .{token.text})))
                    else
                        std.fmt.parseFloat(f64, token.text) catch return self.emitDiagnostics("`{s}` is not a valid number!", .{token.text});

                    return ast.Expression{
                        .location = token.location,
                        .type = .{
                            .number_literal = val,
                        },
                    };
                },
                .string_literal => {
                    std.debug.assert(token.text.len >= 2);
                    return ast.Expression{
                        .location = token.location,
                        .type = .{
                            .string_literal = self.escapeString(token.text[1 .. token.text.len - 1]) catch return self.emitDiagnostics("Invalid escape sequence in {s}!", .{token.text}),
                        },
                    };
                },
                .character_literal => {
                    std.debug.assert(token.text.len >= 2);

                    const escaped_text = self.escapeString(token.text[1 .. token.text.len - 1]) catch return self.emitDiagnostics("Invalid escape sequence in {s}!", .{token.text});

                    var value: u21 = undefined;

                    if (escaped_text.len == 0) {
                        return error.SyntaxError;
                    } else if (escaped_text.len == 1) {
                        // this is a shortcut for non-utf8 encoded files.
                        // it's not a perfect heuristic, but it's okay.
                        value = escaped_text[0];
                    } else {
                        const utf8_len = std.unicode.utf8ByteSequenceLength(escaped_text[0]) catch return self.emitDiagnostics("Invalid utf8 sequence: `{s}`!", .{escaped_text});
                        if (escaped_text.len != utf8_len)
                            return error.SyntaxError;
                        value = std.unicode.utf8Decode(escaped_text[0..utf8_len]) catch return self.emitDiagnostics("Invalid utf8 sequence: `{s}`!", .{escaped_text});
                    }

                    return ast.Expression{
                        .location = token.location,
                        .type = .{
                            .number_literal = @as(f64, @floatFromInt(value)),
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
        .allocator = arena.allocator(),
        .sequence = sequence,
        .diagnostics = diagnostics,
    };

    while (parser.index < parser.sequence.len) {
        const state = parser.saveState();

        // look-ahead one token and try accepting a "function" keyword,
        // use that to select between parsing a function or a statement.
        if (parser.accept(Parser.is(.function))) |_| {
            // we need to unaccept the function token
            parser.restoreState(state);

            const fun = try parser.acceptFunction();
            try functions.append(alloc, fun);
        } else |_| {
            // no need to unaccept here as we didn't accept in the first place
            const stmt = parser.acceptStatement() catch |err| switch (err) {
                error.SyntaxError => {
                    // Do some recovery here:
                    try diagnostics.emit(.@"error", parser.getCurrentLocation(), "syntax error!", .{});

                    while (parser.index < parser.sequence.len) {
                        const recovery_state = parser.saveState();
                        const tok = try parser.accept(Parser.any);
                        if (tok.type == .@";")
                            break;

                        // We want to be able to parse the next function properly
                        // even if we have syntax errors.
                        if (tok.type == .function) {
                            parser.restoreState(recovery_state);
                            break;
                        }
                    }

                    continue;
                },

                else => |e| return e,
            };
            try root_script.append(alloc, stmt);
        }
    }

    return ast.Program{
        .arena = arena,
        .root_script = try root_script.toOwnedSlice(alloc),
        .functions = try functions.toOwnedSlice(alloc),
    };
}

fn testTokenize(str: []const u8) ![]lexer.Token {
    var result = std.ArrayList(lexer.Token).empty;
    var tokenizer = lexer.Tokenizer.init("testsrc", str);

    while (true) {
        switch (tokenizer.next()) {
            .end_of_file => return result.toOwnedSlice(std.testing.allocator),
            .invalid_sequence => unreachable, // we don't do that here
            .token => |token| try result.append(std.testing.allocator, token),
        }
    }
}

fn expectEqual(expected: anytype, actual: anytype) !void {
    const T = @TypeOf(expected);
    return try std.testing.expectEqual(expected, @as(T, actual));
}

const expectEqualStrings = std.testing.expectEqualStrings;

test "empty file parsing" {
    var diagnostics = diag.Diagnostics.init(std.testing.allocator);
    defer diagnostics.deinit();

    var pgm = try parse(std.testing.allocator, &diagnostics, &[_]lexer.Token{});
    defer pgm.deinit();

    // assert that an empty file results in a empty AST
    try expectEqual(@as(usize, 0), pgm.root_script.len);
    try expectEqual(@as(usize, 0), pgm.functions.len);

    // assert that we didn't encounter syntax errors
    try expectEqual(@as(usize, 0), diagnostics.messages.items.len);
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

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.empty, pgm.root_script[0].type);
}

test "parse single empty function" {
    // 0 params
    {
        var pgm = try parseTest("function empty(){}");
        defer pgm.deinit();

        try expectEqual(@as(usize, 1), pgm.functions.len);
        try expectEqual(@as(usize, 0), pgm.root_script.len);

        const fun = pgm.functions[0];

        try std.testing.expectEqualStrings("empty", fun.name);
        try expectEqual(ast.Statement.Type.block, fun.body.type);
        try expectEqual(@as(usize, 0), fun.body.type.block.len);
        try expectEqual(@as(usize, 0), fun.parameters.len);
    }

    // 1 param
    {
        var pgm = try parseTest("function empty(p0){}");
        defer pgm.deinit();

        try expectEqual(@as(usize, 1), pgm.functions.len);
        try expectEqual(@as(usize, 0), pgm.root_script.len);

        const fun = pgm.functions[0];

        try std.testing.expectEqualStrings("empty", fun.name);
        try expectEqual(ast.Statement.Type.block, fun.body.type);
        try expectEqual(@as(usize, 0), fun.body.type.block.len);
        try expectEqual(@as(usize, 1), fun.parameters.len);
        try std.testing.expectEqualStrings("p0", fun.parameters[0]);
    }

    // 3 param
    {
        var pgm = try parseTest("function empty(p0,p1,p2){}");
        defer pgm.deinit();

        try expectEqual(@as(usize, 1), pgm.functions.len);
        try expectEqual(@as(usize, 0), pgm.root_script.len);

        const fun = pgm.functions[0];

        try std.testing.expectEqualStrings("empty", fun.name);
        try expectEqual(ast.Statement.Type.block, fun.body.type);
        try expectEqual(@as(usize, 0), fun.body.type.block.len);
        try expectEqual(@as(usize, 3), fun.parameters.len);
        try std.testing.expectEqualStrings("p0", fun.parameters[0]);
        try std.testing.expectEqualStrings("p1", fun.parameters[1]);
        try std.testing.expectEqualStrings("p2", fun.parameters[2]);
    }
}

test "parse multiple top level statements" {
    // test with the simplest of all statements:
    // the empty one
    var pgm = try parseTest(";;;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 3), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.empty, pgm.root_script[0].type);
    try expectEqual(ast.Statement.Type.empty, pgm.root_script[1].type);
    try expectEqual(ast.Statement.Type.empty, pgm.root_script[2].type);
}

test "parse mixed function and top level statement" {
    var pgm = try parseTest(";function n(){};");
    defer pgm.deinit();

    try expectEqual(@as(usize, 1), pgm.functions.len);
    try expectEqual(@as(usize, 2), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.empty, pgm.root_script[0].type);
    try expectEqual(ast.Statement.Type.empty, pgm.root_script[1].type);

    const fun = pgm.functions[0];

    try std.testing.expectEqualStrings("n", fun.name);
    try expectEqual(ast.Statement.Type.block, fun.body.type);
    try expectEqual(@as(usize, 0), fun.body.type.block.len);
    try expectEqual(@as(usize, 0), fun.parameters.len);
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

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 3), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.block, pgm.root_script[0].type);
    try expectEqual(ast.Statement.Type.block, pgm.root_script[1].type);
    try expectEqual(ast.Statement.Type.block, pgm.root_script[2].type);

    try expectEqual(@as(usize, 0), pgm.root_script[0].type.block.len);
    try expectEqual(@as(usize, 3), pgm.root_script[1].type.block.len);
    try expectEqual(@as(usize, 0), pgm.root_script[2].type.block.len);

    try expectEqual(ast.Statement.Type.block, pgm.root_script[1].type.block[0].type);
    try expectEqual(ast.Statement.Type.block, pgm.root_script[1].type.block[1].type);
    try expectEqual(ast.Statement.Type.empty, pgm.root_script[1].type.block[2].type);

    try expectEqual(@as(usize, 1), pgm.root_script[1].type.block[0].type.block.len);
    try expectEqual(@as(usize, 2), pgm.root_script[1].type.block[1].type.block.len);

    try expectEqual(ast.Statement.Type.empty, pgm.root_script[1].type.block[1].type.block[0].type);
    try expectEqual(ast.Statement.Type.empty, pgm.root_script[1].type.block[1].type.block[0].type);
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

    try expectEqual(@as(usize, 1), pgm.functions.len);
    try expectEqual(@as(usize, 0), pgm.root_script.len);

    const fun = pgm.functions[0];

    try expectEqual(ast.Statement.Type.block, fun.body.type);

    const items = fun.body.type.block;

    try expectEqual(ast.Statement.Type.block, items[0].type);
    try expectEqual(ast.Statement.Type.block, items[1].type);
    try expectEqual(ast.Statement.Type.block, items[2].type);

    try expectEqual(@as(usize, 0), items[0].type.block.len);
    try expectEqual(@as(usize, 3), items[1].type.block.len);
    try expectEqual(@as(usize, 0), items[2].type.block.len);

    try expectEqual(ast.Statement.Type.block, items[1].type.block[0].type);
    try expectEqual(ast.Statement.Type.block, items[1].type.block[1].type);
    try expectEqual(ast.Statement.Type.empty, items[1].type.block[2].type);

    try expectEqual(@as(usize, 1), items[1].type.block[0].type.block.len);
    try expectEqual(@as(usize, 2), items[1].type.block[1].type.block.len);

    try expectEqual(ast.Statement.Type.empty, items[1].type.block[1].type.block[0].type);
    try expectEqual(ast.Statement.Type.empty, items[1].type.block[1].type.block[0].type);
}

test "parsing break" {
    var pgm = try parseTest("break;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.@"break", pgm.root_script[0].type);
}

test "parsing continue" {
    var pgm = try parseTest("continue;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.@"continue", pgm.root_script[0].type);
}

test "parsing while" {
    var pgm = try parseTest("while(1) { }");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.while_loop, pgm.root_script[0].type);
    try expectEqual(ast.Statement.Type.block, pgm.root_script[0].type.while_loop.body.type);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.while_loop.condition.type);
}

test "parsing for" {
    var pgm = try parseTest("for(name in 1) { }");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.for_loop, pgm.root_script[0].type);
    try expectEqualStrings("name", pgm.root_script[0].type.for_loop.variable);
    try expectEqual(ast.Statement.Type.block, pgm.root_script[0].type.for_loop.body.type);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.for_loop.source.type);
}

test "parsing single if" {
    var pgm = try parseTest("if(1) { }");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.if_statement, pgm.root_script[0].type);
    try expectEqual(ast.Statement.Type.block, pgm.root_script[0].type.if_statement.true_body.type);
    try expectEqual(@as(?*ast.Statement, null), pgm.root_script[0].type.if_statement.false_body);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.if_statement.condition.type);
}

test "parsing if-else" {
    var pgm = try parseTest("if(1) { } else ;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.if_statement, pgm.root_script[0].type);
    try expectEqual(ast.Statement.Type.block, pgm.root_script[0].type.if_statement.true_body.type);
    try expectEqual(ast.Statement.Type.empty, pgm.root_script[0].type.if_statement.false_body.?.type);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.if_statement.condition.type);
}

test "parsing return (void)" {
    var pgm = try parseTest("return;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.return_void, pgm.root_script[0].type);
}

test "parsing return (value)" {
    var pgm = try parseTest("return 1;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.return_expr, pgm.root_script[0].type);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.return_expr.type);
}

test "parsing var declaration (no value)" {
    var pgm = try parseTest("var name;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.declaration, pgm.root_script[0].type);
    try expectEqualStrings("name", pgm.root_script[0].type.declaration.variable);
    try expectEqual(false, pgm.root_script[0].type.declaration.is_const);
    try expectEqual(@as(?ast.Expression, null), pgm.root_script[0].type.declaration.initial_value);
}

test "parsing var declaration (initial value)" {
    var pgm = try parseTest("var name = 1;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.declaration, pgm.root_script[0].type);
    try expectEqualStrings("name", pgm.root_script[0].type.declaration.variable);
    try expectEqual(false, pgm.root_script[0].type.declaration.is_const);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.declaration.initial_value.?.type);
}

test "parsing const declaration (no value)" {
    var pgm = try parseTest("const name;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.declaration, pgm.root_script[0].type);
    try expectEqualStrings("name", pgm.root_script[0].type.declaration.variable);
    try expectEqual(true, pgm.root_script[0].type.declaration.is_const);
    try expectEqual(@as(?ast.Expression, null), pgm.root_script[0].type.declaration.initial_value);
}

test "parsing const declaration (initial value)" {
    var pgm = try parseTest("const name = 1;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.declaration, pgm.root_script[0].type);
    try expectEqualStrings("name", pgm.root_script[0].type.declaration.variable);
    try expectEqual(true, pgm.root_script[0].type.declaration.is_const);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.declaration.initial_value.?.type);
}

test "parsing assignment" {
    var pgm = try parseTest("1 = 1;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.assignment, pgm.root_script[0].type);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.target.type);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.value.type);
}

test "parsing operator-assignment addition" {
    var pgm = try parseTest("1 += 1;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.assignment, pgm.root_script[0].type);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.target.type);
    try expectEqual(ast.Expression.Type.binary_operator, pgm.root_script[0].type.assignment.value.type);
    try expectEqual(ast.BinaryOperator.add, pgm.root_script[0].type.assignment.value.type.binary_operator.operator);
}

test "parsing operator-assignment subtraction" {
    var pgm = try parseTest("1 -= 1;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.assignment, pgm.root_script[0].type);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.target.type);
    try expectEqual(ast.Expression.Type.binary_operator, pgm.root_script[0].type.assignment.value.type);
    try expectEqual(ast.BinaryOperator.subtract, pgm.root_script[0].type.assignment.value.type.binary_operator.operator);
}

test "parsing operator-assignment multiplication" {
    var pgm = try parseTest("1 *= 1;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.assignment, pgm.root_script[0].type);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.target.type);
    try expectEqual(ast.Expression.Type.binary_operator, pgm.root_script[0].type.assignment.value.type);
    try expectEqual(ast.BinaryOperator.multiply, pgm.root_script[0].type.assignment.value.type.binary_operator.operator);
}

test "parsing operator-assignment division" {
    var pgm = try parseTest("1 /= 1;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.assignment, pgm.root_script[0].type);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.target.type);
    try expectEqual(ast.Expression.Type.binary_operator, pgm.root_script[0].type.assignment.value.type);
    try expectEqual(ast.BinaryOperator.divide, pgm.root_script[0].type.assignment.value.type.binary_operator.operator);
}

test "parsing operator-assignment modulus" {
    var pgm = try parseTest("1 %= 1;");
    defer pgm.deinit();

    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);

    try expectEqual(ast.Statement.Type.assignment, pgm.root_script[0].type);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.target.type);
    try expectEqual(ast.Expression.Type.binary_operator, pgm.root_script[0].type.assignment.value.type);
    try expectEqual(ast.BinaryOperator.modulus, pgm.root_script[0].type.assignment.value.type.binary_operator.operator);
}

/// Parse a program with `1 = $(EXPR)`, will return `$(EXPR)`
fn getTestExpr(pgm: ast.Program) !ast.Expression {
    try expectEqual(@as(usize, 0), pgm.functions.len);
    try expectEqual(@as(usize, 1), pgm.root_script.len);
    try expectEqual(ast.Expression.Type.number_literal, pgm.root_script[0].type.assignment.target.type);

    const expr = pgm.root_script[0].type.assignment.value;

    return expr;
}

test "integer literal" {
    var pgm = try parseTest("1 = 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.number_literal, expr.type);
    try std.testing.expectApproxEqAbs(@as(f64, 1), expr.type.number_literal, 0.000001);
}

test "decimal literal" {
    var pgm = try parseTest("1 = 1.0;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.number_literal, expr.type);
    try std.testing.expectApproxEqAbs(@as(f64, 1), expr.type.number_literal, 0.000001);
}

test "hexadecimal literal" {
    var pgm = try parseTest("1 = 0x1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.number_literal, expr.type);
    try std.testing.expectApproxEqAbs(@as(f64, 1), expr.type.number_literal, 0.000001);
}

test "string literal" {
    var pgm = try parseTest("1 = \"string content\";");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.string_literal, expr.type);
    try expectEqualStrings("string content", expr.type.string_literal);
}

test "escaped string literal" {
    var pgm = try parseTest("1 = \"\\\"content\\\"\";");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.string_literal, expr.type);
    try expectEqualStrings("\"content\"", expr.type.string_literal);
}

test "character literal" {
    var pgm = try parseTest("1 = ' ';");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.number_literal, expr.type);
    try expectEqual(@as(f64, ' '), expr.type.number_literal);
}

test "variable reference" {
    var pgm = try parseTest("1 = variable_name;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.variable_expr, expr.type);
    try expectEqualStrings("variable_name", expr.type.variable_expr);
}

test "addition expression" {
    var pgm = try parseTest("1 = 1 + 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.add, expr.type.binary_operator.operator);
}

test "subtraction expression" {
    var pgm = try parseTest("1 = 1 - 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.subtract, expr.type.binary_operator.operator);
}

test "multiplication expression" {
    var pgm = try parseTest("1 = 1 * 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.multiply, expr.type.binary_operator.operator);
}

test "division expression" {
    var pgm = try parseTest("1 = 1 / 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.divide, expr.type.binary_operator.operator);
}

test "modulus expression" {
    var pgm = try parseTest("1 = 1 % 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.modulus, expr.type.binary_operator.operator);
}

test "boolean or expression" {
    var pgm = try parseTest("1 = 1 or 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.boolean_or, expr.type.binary_operator.operator);
}

test "boolean and expression" {
    var pgm = try parseTest("1 = 1 and 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.boolean_and, expr.type.binary_operator.operator);
}

test "greater than expression" {
    var pgm = try parseTest("1 = 1 > 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.greater_than, expr.type.binary_operator.operator);
}

test "less than expression" {
    var pgm = try parseTest("1 = 1 < 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.less_than, expr.type.binary_operator.operator);
}

test "greater or equal than expression" {
    var pgm = try parseTest("1 = 1 >= 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.greater_or_equal_than, expr.type.binary_operator.operator);
}

test "less or equal than expression" {
    var pgm = try parseTest("1 = 1 <= 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.less_or_equal_than, expr.type.binary_operator.operator);
}

test "equal expression" {
    var pgm = try parseTest("1 = 1 == 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.equal, expr.type.binary_operator.operator);
}

test "different expression" {
    var pgm = try parseTest("1 = 1 != 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.different, expr.type.binary_operator.operator);
}

test "operator precedence (binaries)" {
    var pgm = try parseTest("1 = 1 + 1 * 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.add, expr.type.binary_operator.operator);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type.binary_operator.rhs.type);
    try expectEqual(ast.BinaryOperator.multiply, expr.type.binary_operator.rhs.type.binary_operator.operator);
}

test "operator precedence (unary and binary mixed)" {
    var pgm = try parseTest("1 = -1 * 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.multiply, expr.type.binary_operator.operator);

    try expectEqual(ast.Expression.Type.unary_operator, expr.type.binary_operator.lhs.type);
    try expectEqual(ast.UnaryOperator.negate, expr.type.binary_operator.lhs.type.unary_operator.operator);
}

test "invers operator precedence with parens" {
    var pgm = try parseTest("1 = 1 * (1 + 1);");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type);
    try expectEqual(ast.BinaryOperator.multiply, expr.type.binary_operator.operator);

    try expectEqual(ast.Expression.Type.binary_operator, expr.type.binary_operator.rhs.type);
    try expectEqual(ast.BinaryOperator.add, expr.type.binary_operator.rhs.type.binary_operator.operator);
}

test "unary minus expression" {
    var pgm = try parseTest("1 = -1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.unary_operator, expr.type);
    try expectEqual(ast.UnaryOperator.negate, expr.type.unary_operator.operator);
}

test "unary not expression" {
    var pgm = try parseTest("1 = not 1;");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.unary_operator, expr.type);
    try expectEqual(ast.UnaryOperator.boolean_not, expr.type.unary_operator.operator);
}

test "single array indexing expression" {
    var pgm = try parseTest("1 = 1[\"\"];");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.array_indexer, expr.type);
    try expectEqual(ast.Expression.Type.number_literal, expr.type.array_indexer.value.type);
    try expectEqual(ast.Expression.Type.string_literal, expr.type.array_indexer.index.type);
}

test "multiple array indexing expressions" {
    var pgm = try parseTest("1 = a[b][c];");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.array_indexer, expr.type);
    try expectEqual(ast.Expression.Type.array_indexer, expr.type.array_indexer.value.type);
    try expectEqual(ast.Expression.Type.variable_expr, expr.type.array_indexer.index.type);
    try expectEqualStrings("c", expr.type.array_indexer.index.type.variable_expr);

    try expectEqual(ast.Expression.Type.variable_expr, expr.type.array_indexer.value.type.array_indexer.value.type);
    try expectEqual(ast.Expression.Type.variable_expr, expr.type.array_indexer.value.type.array_indexer.index.type);

    try expectEqualStrings("a", expr.type.array_indexer.value.type.array_indexer.value.type.variable_expr);
    try expectEqualStrings("b", expr.type.array_indexer.value.type.array_indexer.index.type.variable_expr);
}

test "zero parameter function call expression" {
    var pgm = try parseTest("1 = foo();");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.function_call, expr.type);
    try expectEqual(ast.Expression.Type.variable_expr, expr.type.function_call.function.type);
    try expectEqual(@as(usize, 0), expr.type.function_call.arguments.len);
}

test "one parameter function call expression" {
    var pgm = try parseTest("1 = foo(a);");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.function_call, expr.type);
    try expectEqual(ast.Expression.Type.variable_expr, expr.type.function_call.function.type);
    try expectEqual(@as(usize, 1), expr.type.function_call.arguments.len);

    try expectEqualStrings("a", expr.type.function_call.arguments[0].type.variable_expr);
}

test "4 parameter function call expression" {
    var pgm = try parseTest("1 = foo(a,b,c,d);");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.function_call, expr.type);
    try expectEqual(ast.Expression.Type.variable_expr, expr.type.function_call.function.type);
    try expectEqual(@as(usize, 4), expr.type.function_call.arguments.len);

    try expectEqualStrings("a", expr.type.function_call.arguments[0].type.variable_expr);
    try expectEqualStrings("b", expr.type.function_call.arguments[1].type.variable_expr);
    try expectEqualStrings("c", expr.type.function_call.arguments[2].type.variable_expr);
    try expectEqualStrings("d", expr.type.function_call.arguments[3].type.variable_expr);
}

test "zero parameter method call expression" {
    var pgm = try parseTest("1 = a.foo();");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.method_call, expr.type);

    try expectEqualStrings("foo", expr.type.method_call.name);
    try expectEqual(ast.Expression.Type.variable_expr, expr.type.method_call.object.type);
    try expectEqual(@as(usize, 0), expr.type.method_call.arguments.len);
}

test "one parameter method call expression" {
    var pgm = try parseTest("1 = a.foo(a);");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.method_call, expr.type);

    try expectEqualStrings("foo", expr.type.method_call.name);
    try expectEqual(ast.Expression.Type.variable_expr, expr.type.method_call.object.type);
    try expectEqual(@as(usize, 1), expr.type.method_call.arguments.len);

    try expectEqualStrings("a", expr.type.method_call.arguments[0].type.variable_expr);
}

test "4 parameter method call expression" {
    var pgm = try parseTest("1 = a.foo(a,b,c,d);");
    defer pgm.deinit();

    const expr = try getTestExpr(pgm);

    try expectEqual(ast.Expression.Type.method_call, expr.type);

    try expectEqualStrings("foo", expr.type.method_call.name);
    try expectEqual(ast.Expression.Type.variable_expr, expr.type.method_call.object.type);
    try expectEqual(@as(usize, 4), expr.type.method_call.arguments.len);

    try expectEqualStrings("a", expr.type.method_call.arguments[0].type.variable_expr);
    try expectEqualStrings("b", expr.type.method_call.arguments[1].type.variable_expr);
    try expectEqualStrings("c", expr.type.method_call.arguments[2].type.variable_expr);
    try expectEqualStrings("d", expr.type.method_call.arguments[3].type.variable_expr);
}

test "full suite parsing" {
    const seq = try testTokenize(@embedFile("test/compiler.lola"));
    defer std.testing.allocator.free(seq);

    var diagnostics = diag.Diagnostics.init(std.testing.allocator);
    defer diagnostics.deinit();

    var pgm = try parse(std.testing.allocator, &diagnostics, seq);
    defer pgm.deinit();

    for (diagnostics.messages.items) |msg| {
        std.log.err("{f}", .{msg});
    }

    // assert that we don't have an empty AST
    try std.testing.expect(pgm.root_script.len > 0);
    try std.testing.expect(pgm.functions.len > 0);

    // assert that we didn't encounter syntax errors
    try expectEqual(@as(usize, 0), diagnostics.messages.items.len);
}
