const std = @import("std");
const builtin = @import("builtin");

/// A wrapper for a nullable pointer type that can be passed to LoLa functions.
pub const Context = union(enum) {
    const Self = @This();

    const TypeId = enum(usize) {
        _,

        pub fn name(self: TypeId) []const u8 {
            return std.mem.sliceTo(@intToPtr([*:0]const u8, @enumToInt(self)), 0);
        }
    };

    fn typeId(comptime T: type) TypeId {
        return @intToEnum(TypeId, @ptrToInt(&struct {
            const str = @typeName(T);
            var name: [str.len:0]u8 = str.*;
        }.name));
    }

    const Opaque = opaque {};

    const Pointer = if (builtin.mode == .Debug)
        struct {
            pub const Store = @This();

            ptr: *Opaque,
            type_id: TypeId,

            pub fn make(comptime T: type, ptr: *T) Store {
                return Store{
                    .ptr = @ptrCast(*Opaque, ptr),
                    .type_id = typeId(T),
                };
            }

            pub fn cast(self: Store, comptime T: type) *T {
                if (typeId(T) != self.type_id) {
                    std.debug.panic("Type mismatch: Expected {s}, but got {s}!", .{ @typeName(T), self.type_id.name() });
                }
                return @ptrCast(*T, @alignCast(@alignOf(T), self.ptr));
            }
        }
    else
        struct {
            pub const Store = *Opaque;

            pub fn make(comptime T: type, ptr: *T) *Opaque {
                return @ptrCast(*Opaque, ptr);
            }

            pub fn cast(self: *Opaque, comptime T: type) *T {
                return @ptrCast(*T, @alignCast(@alignOf(T), self));
            }
        };

    empty: void,
    content: Pointer.Store,

    pub fn init(comptime T: type, ptr: *T) Self {
        return Self{
            .content = Pointer.make(T, ptr),
        };
    }

    pub fn get(self: Self, comptime T: type) *T {
        return Pointer.cast(self.content, T);
    }
};
