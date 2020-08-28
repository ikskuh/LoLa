const std = @import("std");

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
