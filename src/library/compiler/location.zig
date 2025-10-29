const std = @import("std");

/// A location in a chunk of text. Can be used to locate tokens and AST structures.
pub const Location = struct {
    /// the name of the file/chunk this location is relative to
    chunk: []const u8,

    /// source line, starting at 1
    line: u32,

    /// source column, starting at 1
    column: u32,

    /// Offset to the start of the location
    offset_start: usize,

    /// Offset to the end of the location
    offset_end: usize,

    pub fn getLength(self: @This()) usize {
        return self.offset_end - self.offset_start;
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        try writer.print("{s}:{d}:{d}", .{ self.chunk, self.line, self.column });
    }

    pub fn merge(a: Location, b: Location) Location {
        // Should emitted from the same chunk
        std.debug.assert(a.chunk.ptr == b.chunk.ptr);

        const min = if (a.offset_start < b.offset_start)
            a
        else
            b;

        return Location{
            .chunk = a.chunk,
            .line = min.line,
            .column = min.column,
            .offset_start = @min(a.offset_start, b.offset_start),
            .offset_end = @max(a.offset_end, b.offset_end),
        };
    }
};
