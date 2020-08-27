const std = @import("std");

const diag = @import("diagnostics.zig");

const TokenType = enum {
    const Self = @This();

    number,
    string_literal,
    identifier,
    comment,
    whitespace,
    @"{",
    @"}",
    @"(",
    @")",
    @"]",
    @"[",
    @"var",
    @"extern",
    @"for",
    @"while",
    @"if",
    @"else",
    @"function",
    @"in",
    @"break",
    @"continue",
    @"return",
    @"and",
    @"or",
    @"not",
    @"+=",
    @"-=",
    @"*=",
    @"/=",
    @"%=",
    @"<=",
    @">=",
    @"<",
    @">",
    @"!=",
    @"==",
    @"=",
    @".",
    @",",
    @";",
    @"+",
    @"-",
    @"*",
    @"/",
    @"%",

    /// Returns `true` when the token type is emitted from the tokenizer,
    /// otherwise `false`.
    pub fn isEmitted(self: Self) bool {
        return switch (self) {
            .comment, .whitespace => false,
            else => true,
        };
    }
};

const keywords = [_][]const u8{
    "var",
    "extern",
    "for",
    "while",
    "if",
    "else",
    "function",
    "in",
    "break",
    "continue",
    "return",
    "and",
    "or",
    "not",
};

/// A location in a chunk of text. Can be used to locate tokens and AST structures.
pub const Location = struct {
    /// the name of the file/chunk this location is relative to
    chunk: []const u8,

    /// source line, starting at 1
    line: u32,

    /// source column, starting at 1
    column: u32,

    /// number of characters this token takes
    length: usize,

    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}:{}:{}", .{ self.chunk, self.line, self.column });
    }
};

/// A single, recognized piece of text in the source file.
pub const Token = struct {
    /// the text that was recognized
    text: []const u8,

    /// the position in the source file
    location: Location,

    /// the type (and parsed value) of the token
    type: TokenType,
};

pub const Tokenizer = struct {
    const Self = @This();

    source: []const u8,
    offset: usize,
    current_location: Location,

    pub fn init(chunk_name: []const u8, source: []const u8) Self {
        return Self{
            .source = source,
            .offset = 0,
            .current_location = Location{
                .line = 1,
                .column = 1,
                .chunk = chunk_name,
                .length = undefined,
            },
        };
    }

    pub fn next(self: *Self) ?Token {
        while (true) {
            const start = self.offset;
            if (nextInternal(self)) |token_type| {
                const end = self.offset;
                std.debug.assert(end > start); // tokens may never be empty!

                var token = Token{
                    .type = token_type,
                    .location = self.current_location,
                    .text = self.source[start..end],
                };

                if (token.type == .identifier) {
                    inline for (keywords) |kwd| {
                        if (std.mem.eql(u8, token.text, kwd)) {
                            token.type = @field(TokenType, kwd);
                            break;
                        }
                    }
                }

                token.location.length = end - start;

                for (token.text) |c| {
                    if (c == '\n') {
                        self.current_location.line += 1;
                        self.current_location.column = 1;
                    } else {
                        self.current_location.column += 1;
                    }
                }

                if (token.type.isEmitted())
                    return token;
            } else {
                return null;
            }
        }
    }

    const Predicate = fn (u8) bool;

    fn accept(self: *Self, predicate: fn (u8) bool) bool {
        if (self.offset >= self.source.len)
            return false;
        if (predicate(self.source[self.offset])) {
            self.offset += 1;
            return true;
        } else {
            return false;
        }
    }

    fn any(c: u8) bool {
        return true;
    }

    fn anyOf(comptime chars: []const u8) Predicate {
        return struct {
            fn pred(c: u8) bool {
                return inline for (chars) |o| {
                    if (c == o)
                        break true;
                } else false;
            }
        }.pred;
    }

    fn noneOf(comptime chars: []const u8) Predicate {
        return struct {
            fn pred(c: u8) bool {
                return inline for (chars) |o| {
                    if (c == o)
                        break false;
                } else true;
            }
        }.pred;
    }

    const whitespace_class = anyOf(" \r\n\t");
    const comment_class = noneOf("\n");
    const identifier_class = anyOf("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_");
    const digit_class = anyOf("0123456789");
    const hexdigit_class = anyOf("0123456789abcdefABCDEF");
    const string_char_class = noneOf("\"\\");

    fn nextInternal(self: *Self) ?TokenType {
        if (self.isEndOfStream())
            return null;

        // copy for shorter code
        const source = self.source;

        if (self.accept(whitespace_class)) {
            while (self.accept(whitespace_class)) {}
            return .whitespace;
        }

        const current_char = source[self.offset];
        self.offset += 1;
        switch (current_char) {
            '=' => return if (self.accept(anyOf("=")))
                .@"=="
            else
                .@"=",

            '!' => return if (self.accept(anyOf("=")))
                .@"!="
            else
                null,

            '.' => return .@".",
            ',' => return .@",",
            ';' => return .@";",
            '{' => return .@"{",
            '}' => return .@"}",
            '(' => return .@"(",
            ')' => return .@")",
            ']' => return .@"]",
            '[' => return .@"[",

            '+' => return if (self.accept(anyOf("=")))
                .@"+="
            else
                .@"+",

            '-' => return if (self.accept(anyOf("=")))
                .@"-="
            else
                .@"-",

            '*' => return if (self.accept(anyOf("=")))
                .@"*="
            else
                .@"*",

            '/' => {
                if (self.accept(anyOf("/"))) {
                    while (self.accept(comment_class)) {}
                    return .comment;
                } else if (self.accept(anyOf("="))) {
                    return .@"/=";
                } else {
                    return .@"/";
                }
            },

            '%' => return if (self.accept(anyOf("=")))
                .@"%="
            else
                .@"%",

            '<' => return if (self.accept(anyOf("=")))
                .@"<="
            else
                .@"<",

            '>' => return if (self.accept(anyOf("=")))
                .@">="
            else
                .@">",

                // parse numbers
            '0'...'9' => {
                while (self.accept(digit_class)) {}
                if (self.accept(anyOf("xX"))) {
                    while (self.accept(hexdigit_class)) {}
                    return .number;
                } else if (self.accept(anyOf("."))) {
                    while (self.accept(digit_class)) {}
                    return .number;
                }
                return .number;
            },

            // parse identifiers
            'a'...'z', 'A'...'Z', '_' => {
                while (self.accept(identifier_class)) {}
                return .identifier;
            },

            // parse strings
            '"' => {
                while (true) {
                    while (self.accept(string_char_class)) {}
                    if (self.accept(anyOf("\""))) {
                        return .string_literal;
                    } else if (self.accept(anyOf("\\"))) {
                        if (self.accept(anyOf("x"))) { // hex literal
                            if (!self.accept(hexdigit_class))
                                return null;
                            if (!self.accept(hexdigit_class))
                                return null;
                        }
                        if (!self.accept(any))
                            return null;
                    } else {
                        return null;
                    }
                }
            },

            else => return null,
        }
    }

    pub fn emitUnrecognizedCharacter(self: *Self, diagnostics: *diag.Diagnostics) !void {
        unreachable;
    }

    /// Returns true when the stream is at the end.
    pub fn isEndOfStream(self: Self) bool {
        return (self.offset >= self.source.len);
    }
};

test "Tokenizer empty string" {
    var tokenizer = Tokenizer.init("??", "");
    std.testing.expectEqual(true, tokenizer.isEndOfStream());
    std.testing.expectEqual(@as(?Token, null), tokenizer.next());
}

test "Tokenizer (tokenize compiler test suite)" {
    var tokenizer = Tokenizer.init("src/test/compiler.lola", @embedFile("../../test/compiler.lola"));
    std.testing.expectEqual(false, tokenizer.isEndOfStream());

    while (true) {
        if (tokenizer.next()) |tok| {
            // Use this for manual validation:
            // std.debug.print("token: {}\n", .{tok});
        } else if (tokenizer.isEndOfStream()) {
            break;
        } else {
            std.debug.print("failed to parse test file at '{}'!\n", .{
                tokenizer.source[tokenizer.offset..],
            });
            // this test should never reach this state, as the test file
            // is validated by hand
            unreachable;
        }
    }
}
