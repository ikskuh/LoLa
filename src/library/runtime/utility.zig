const std = @import("std");

pub fn clampFixedString(str: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, str, 0)) |off| {
        return str[0..off];
    } else {
        return str;
    }
}
