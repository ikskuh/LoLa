const std = @import("std");

const Diagnostics = @import("diagnostics.zig").Diagnostics;

pub const TokenType = enum {
    const Self = @This();

    number_literal,
    string_literal,
    character_literal,
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
    @"const",
    @"for",
    @"while",
    @"if",
    @"else",
    function,
    in,
    @"break",
    @"continue",
    @"return",
    @"and",
    @"or",
    not,
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
    "const",
};

pub const Location = @import("location.zig").Location;

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

    /// Result from a tokenization process
    const Result = union(enum) {
        token: Token,
        end_of_file: void,
        invalid_sequence: []const u8,
    };

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
                .offset_start = undefined,
                .offset_end = undefined,
            },
        };
    }

    pub fn next(self: *Self) Result {
        while (true) {
            const start = self.offset;
            if (start >= self.source.len)
                return .end_of_file;

            if (nextInternal(self)) |token_type| {
                const end = self.offset;
                std.debug.assert(end > start); // tokens may never be empty!

                var token = Token{
                    .type = token_type,
                    .location = self.current_location,
                    .text = self.source[start..end],
                };

                // std.debug.print("token: `{}`\n", .{token.text});

                if (token.type == .identifier) {
                    inline for (keywords) |kwd| {
                        if (std.mem.eql(u8, token.text, kwd)) {
                            token.type = @field(TokenType, kwd);
                            break;
                        }
                    }
                }

                token.location.offset_start = start;
                token.location.offset_end = end;

                for (token.text) |c| {
                    if (c == '\n') {
                        self.current_location.line += 1;
                        self.current_location.column = 1;
                    } else {
                        self.current_location.column += 1;
                    }
                }

                if (token.type.isEmitted())
                    return Result{ .token = token };
            } else {
                while (self.accept(invalid_char_class)) {}
                const end = self.offset;

                self.current_location.offset_start = start;
                self.current_location.offset_end = end;

                return Result{ .invalid_sequence = self.source[start..end] };
            }
        }
    }

    const Predicate = fn (u8) bool;

    fn accept(self: *Self, predicate: *const fn (u8) bool) bool {
        if (self.offset >= self.source.len)
            return false;
        const c = self.source[self.offset];
        const accepted = predicate(c);
        // std.debug.print("{c} → {}\n", .{
        //     c, accepted,
        // });
        if (accepted) {
            self.offset += 1;
            return true;
        } else {
            return false;
        }
    }

    fn any(c: u8) bool {
        _ = c;
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

    const invalid_char_class = noneOf(" \r\n\tABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_0123456789+-*/%={}()[]<>\"\'.,;!");
    const whitespace_class = anyOf(" \r\n\t");
    const comment_class = noneOf("\n");
    const identifier_class = anyOf("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_0123456789");
    const digit_class = anyOf("0123456789");
    const hexdigit_class = anyOf("0123456789abcdefABCDEF");
    const string_char_class = noneOf("\"\\");
    const character_char_class = noneOf("\'\\");

    fn nextInternal(self: *Self) ?TokenType {
        std.debug.assert(self.offset < self.source.len);

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
                    return .number_literal;
                } else if (self.accept(anyOf("."))) {
                    while (self.accept(digit_class)) {}
                    return .number_literal;
                }
                return .number_literal;
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
                        } else {
                            if (!self.accept(any))
                                return null;
                        }
                    } else {
                        return null;
                    }
                }
            },

            // parse character literals
            '\'' => {
                while (true) {
                    while (self.accept(character_char_class)) {}
                    if (self.accept(anyOf("\'"))) {
                        return .character_literal;
                    } else if (self.accept(anyOf("\\"))) {
                        if (self.accept(anyOf("x"))) { // hex literal
                            if (!self.accept(hexdigit_class))
                                return null;
                            if (!self.accept(hexdigit_class))
                                return null;
                        } else {
                            if (!self.accept(any))
                                return null;
                        }
                    } else {
                        return null;
                    }
                }
            },

            else => return null,
        }
    }
};

pub fn tokenize(allocator: std.mem.Allocator, diagnostics: *Diagnostics, chunk_name: []const u8, source: []const u8) ![]Token {
    var result = std.ArrayList(Token).empty;
    var tokenizer = Tokenizer.init(chunk_name, source);

    while (true) {
        switch (tokenizer.next()) {
            .end_of_file => return result.toOwnedSlice(allocator),
            .invalid_sequence => |seq| {
                try diagnostics.emit(.@"error", tokenizer.current_location, "invalid byte sequence: {X}", .{
                    seq,
                });
            },
            .token => |token| try result.append(allocator, token),
        }
    }
}

fn expectEqual(expected: anytype, actual: anytype) !void {
    const T = @TypeOf(expected);
    return try std.testing.expectEqual(expected, @as(T, actual));
}

const expectEqualStrings = std.testing.expectEqualStrings;

test "Tokenizer empty string" {
    var tokenizer = Tokenizer.init("??", "");
    try expectEqual(std.meta.Tag(Tokenizer.Result).end_of_file, tokenizer.next());
}

test "Tokenizer invalid bytes" {
    var tokenizer = Tokenizer.init("??", "\\``?`a##§");
    {
        const item = tokenizer.next();
        try expectEqual(std.meta.Tag(Tokenizer.Result).invalid_sequence, item);
        try expectEqualStrings("\\``?`", item.invalid_sequence);
    }
    {
        const item = tokenizer.next();
        try expectEqual(std.meta.Tag(Tokenizer.Result).token, item);
        try expectEqualStrings("a", item.token.text);
    }
    {
        const item = tokenizer.next();
        try expectEqual(std.meta.Tag(Tokenizer.Result).invalid_sequence, item);
        try expectEqualStrings("##§", item.invalid_sequence);
    }
}

test "Tokenizer (tokenize compiler test suite)" {
    var tokenizer = Tokenizer.init("src/test/compiler.lola", @embedFile("test/compiler.lola"));

    while (true) {
        switch (tokenizer.next()) {
            .token => {

                // Use this for manual validation:
                // std.debug.print("token: {}\n", .{tok});
            },
            .end_of_file => break,
            .invalid_sequence => |seq| {
                std.debug.print("failed to parse test file at `{s}`!\n", .{
                    seq,
                });
                // this test should never reach this state, as the test file
                // is validated by hand
                unreachable;
            },
        }
    }
}

test "tokenize" {
    // TODO: Implement meaningful test
    _ = tokenize;
}
