const std = @import("std");

usingnamespace @import("lola");

const Length = struct {
    const Self = @This();

    fn invoke(self: Self, args: []const lola.Value) !lola.Value {
        if (args.len != 1)
            return error.InvalidArgs;
        return switch (args[0]) {
            .string => |str| lola.Value.initNumber(@intToFloat(f64, str.contents.len)),
            .array => |arr| lola.Value.initNumber(@intToFloat(f64, arr.contents.len)),
            else => error.TypeMismatch,
        };
    }
};

pub fn installFor(environment: *Environment) !void {
    // TODO: Implement
}
