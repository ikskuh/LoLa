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

            const start = try self.accept(oneOf(.{
                .@";",
                .@"{",
                .@"while",
                .@"if",
            }));

            switch (start.type) {
                .@";" => return ast.Statement{
                    .location = start.location,
                    .type = .empty,
                },
                .@"{" => {
                    // this is a block. Rewind and call block parser:
                    self.restoreState(state);
                    return try self.acceptBlock();
                },
                .@"while" => {
                    unreachable;
                },
                .@"if" => {
                    unreachable;
                },
                else => unreachable,
            }
        }

        fn acceptExpression(self: *Self) ParseError!ast.Expression {
            const expr = self.accept(is(.number));
            return ast.Expression{
                .location = expr.location,
                .type = .{
                    .number = 3.1415,
                },
            };
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

    std.testing.expectEqual(ast.Statement.StatementType.empty, pgm.root_script[0].type);
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
        std.testing.expectEqual(ast.Statement.StatementType.block, fun.body.type);
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
        std.testing.expectEqual(ast.Statement.StatementType.block, fun.body.type);
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
        std.testing.expectEqual(ast.Statement.StatementType.block, fun.body.type);
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

    std.testing.expectEqual(ast.Statement.StatementType.empty, pgm.root_script[0].type);
    std.testing.expectEqual(ast.Statement.StatementType.empty, pgm.root_script[1].type);
    std.testing.expectEqual(ast.Statement.StatementType.empty, pgm.root_script[2].type);
}

test "parse mixed function and top level statement" {
    var pgm = try parseTest(";function n(){};");
    defer pgm.deinit();

    std.testing.expectEqual(@as(usize, 1), pgm.functions.len);
    std.testing.expectEqual(@as(usize, 2), pgm.root_script.len);

    std.testing.expectEqual(ast.Statement.StatementType.empty, pgm.root_script[0].type);
    std.testing.expectEqual(ast.Statement.StatementType.empty, pgm.root_script[1].type);

    const fun = pgm.functions[0];

    std.testing.expectEqualStrings("n", fun.name);
    std.testing.expectEqual(ast.Statement.StatementType.block, fun.body.type);
    std.testing.expectEqual(@as(usize, 0), fun.body.type.block.len);
    std.testing.expectEqual(@as(usize, 0), fun.parameters.len);
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
