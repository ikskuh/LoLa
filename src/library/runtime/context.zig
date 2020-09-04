const std = @import("std");

/// A wrapper for a nullable pointer type that can be passed to LoLa functions.
pub const Context = union(enum) {
    const Self = @This();
    const Opaque = @Type(.Opaque);

    empty: void,
    content: *Opaque,

    pub fn initVoid() Self {
        return Self{
            .empty = {},
        };
    }

    pub fn init(comptime T: type, ptr: *T) Self {
        return Self{
            .content = @ptrCast(*Opaque, ptr),
        };
    }

    pub fn get(self: Self, comptime T: type) *T {
        return @ptrCast(*T, @alignCast(@alignOf(T), self.content));
    }
};
