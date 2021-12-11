const std = @import("std");

pub const EscapedStringIterator = struct {
    slice: []const u8,
    position: u8,

    pub fn init(slice: []const u8) @This() {
        return @This(){
            .slice = slice,
            .position = 0,
        };
    }

    pub fn next(self: *@This()) error{IncompleteEscapeSequence}!?u8 {
        if (self.position >= self.slice.len)
            return null;

        switch (self.slice[self.position]) {
            '\\' => {
                self.position += 1;
                if (self.position == self.slice.len)
                    return error.IncompleteEscapeSequence;
                const c = self.slice[self.position];
                self.position += 1;
                return switch (c) {
                    'a' => 7,
                    'b' => 8,
                    't' => 9,
                    'n' => 10,
                    'r' => 13,
                    'e' => 27,
                    '\"' => 34,
                    '\'' => 39,
                    'x' => blk: {
                        if (self.position + 2 > self.slice.len)
                            return error.IncompleteEscapeSequence;
                        const str = self.slice[self.position..][0..2];
                        self.position += 2;
                        break :blk std.fmt.parseInt(u8, str, 16) catch return error.IncompleteEscapeSequence;
                    },
                    else => c,
                };
            },

            else => {
                self.position += 1;
                return self.slice[self.position - 1];
            },
        }
    }
};

/// Applies all known string escape codes to the given input string,
/// returning a freshly allocated string.
pub fn escapeString(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var iterator = EscapedStringIterator{
        .slice = input,
        .position = 0,
    };

    var len: usize = 0;
    while (try iterator.next()) |_| {
        len += 1;
    }

    iterator.position = 0;

    const result = try allocator.alloc(u8, len);
    var i: usize = 0;
    while (iterator.next() catch unreachable) |c| {
        result[i] = c;
        i += 1;
    }
    std.debug.assert(i == len);

    return result;
}

test "escape empty string" {
    const str = try escapeString(std.testing.allocator, "");
    defer std.testing.allocator.free(str);

    try std.testing.expectEqualStrings("", str);
}

test "escape string without escape codes" {
    const str = try escapeString(std.testing.allocator, "ixtAOy9UbcIsIijUi42mtzOSwTiNolZAajBeS9W2PCgkyt7fDbuSQcjqKVRoBhalPBwThIkcVRa6W6tK2go1m7V2WoIrQNxuPzpf");
    defer std.testing.allocator.free(str);

    try std.testing.expectEqualStrings("ixtAOy9UbcIsIijUi42mtzOSwTiNolZAajBeS9W2PCgkyt7fDbuSQcjqKVRoBhalPBwThIkcVRa6W6tK2go1m7V2WoIrQNxuPzpf", str);
}

// \a 7   Alert / Bell
// \b 8   Backspace
// \t 9   Horizontal Tab
// \n 10  Line Feed
// \r 13  Carriage Return
// \e 27  Escape
// \" 34  Double Quotes
// \' 39  Single Quote

test "escape string with predefined escape sequences" {
    const str = try escapeString(std.testing.allocator, " \\a \\b \\t \\n \\r \\e \\\" \\' ");
    defer std.testing.allocator.free(str);

    try std.testing.expectEqualStrings(" \x07 \x08 \x09 \x0A \x0D \x1B \" \' ", str);
}

test "escape string with hexadecimal escape sequences" {
    const str = try escapeString(std.testing.allocator, " \\xcA \\x84 \\x2d \\x75 \\xb7 \\xF1 \\xf3 \\x9e ");
    defer std.testing.allocator.free(str);

    try std.testing.expectEqualStrings(" \xca \x84 \x2d \x75 \xb7 \xf1 \xf3 \x9e ", str);
}

test "incomplete normal escape sequence" {
    try std.testing.expectError(error.IncompleteEscapeSequence, escapeString(std.testing.allocator, "\\"));
}

test "incomplete normal hex sequence" {
    try std.testing.expectError(error.IncompleteEscapeSequence, escapeString(std.testing.allocator, "\\x"));
    try std.testing.expectError(error.IncompleteEscapeSequence, escapeString(std.testing.allocator, "\\xA"));
}

test "invalid hex sequence" {
    try std.testing.expectError(error.IncompleteEscapeSequence, escapeString(std.testing.allocator, "\\xXX"));
}

test "escape string with tight predefined escape sequence" {
    const str = try escapeString(std.testing.allocator, "\\a");
    defer std.testing.allocator.free(str);

    try std.testing.expectEqualStrings("\x07", str);
}

test "escape string with tight hexadecimal escape sequence" {
    const str = try escapeString(std.testing.allocator, "\\xca");
    defer std.testing.allocator.free(str);

    try std.testing.expectEqualStrings("\xca", str);
}
