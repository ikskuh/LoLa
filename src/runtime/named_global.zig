const std = @import("std");

usingnamespace @import("value.zig");

// pub const SmartGlobal = struct {
//     const Self = @This();

//     pub const Context = struct {
//         raw: usize,

//         pub fn init(comptime T: type, ptr: *T) Context {
//             return Context{ .raw = @ptrToInt(ptr) };
//         }

//         pub fn get(self: Context, comptime T: type) *T {
//             return @intToPtr(*T, self.raw);
//         }
//     };

//     pub const Getter = fn (ctx: Context) Value;
//     pub const Setter = fn (ctx: Context, value: Value) void;

//     pub fn initRead(ctx: Context, get: Getter) Self {
//         return Self{ .get = get, .set = null, .context = ctx };
//     }

//     pub fn initWrite(ctx: Context, set: Setter) Self {
//         return Self{ .get = null, .set = set, .context = ctx };
//     }

//     pub fn initReadWrite(ctx: Context, get: Getter, set: Setter) Self {
//         return Self{ .get = get, .set = set, .context = ctx };
//     }

//     context: Context,
//     get: ?Getter,
//     set: ?Setter,
// };

// test "SmartGlobal" {
//     var value = Value.initNumber(42);

//     const MySmarty = struct {
//         fn read(ctx: SmartGlobal.Context) Value {
//             return ctx.get(Value).*;
//         }

//         fn write(ctx: SmartGlobal.Context, val: Value) void {
//             ctx.get(Value).* = val;
//         }
//     };

//     var sg1 = SmartGlobal.initReadWrite(SmartGlobal.Context.init(Value, &value), MySmarty.read, MySmarty.write);

//     std.debug.assert(value.eql((sg1.get orelse unreachable)(sg1.context)));

//     (sg1.set orelse unreachable)(sg1.context, Value.initBoolean(true));

//     std.debug.assert(value.eql(Value.initBoolean(true)));
// }

/// A variable provided by external means.
pub const NamedGlobal = union(enum) {
    const Self = @This();

    stored: Value,
    referenced: *Value,
    // smart: SmartGlobal,

    pub fn initStored(value: Value) Self {
        return Self{ .stored = value };
    }

    pub fn initReferenced(value: *Value) Self {
        return Self{ .referenced = value };
    }

    // pub fn initSmart(value: SmartGlobal) Self {
    //     return Self{ .smart = value };
    // }

    /// Gets the value of this variable.
    pub fn get(self: Self) error{ReadProtected}!Value {
        return switch (self) {
            .stored => |val| val,
            .referenced => |ref| ref.*,
            // .smart => |smart| if (smart.get) |g| g(smart.context) else return error.ReadProtected,
        };
    }

    /// Sets the value of this variable.
    pub fn set(self: *Self, value: Value) error{WriteProtected}!void {
        switch (self.*) {
            .stored => |*val| val.* = value,
            .referenced => |ref| ref.* = value,
            // .smart => |smart| if (smart.set) |s| s(smart.context, value) else return error.WriteProtected,
        }
    }
};

test "NamedGlobal (stored)" {
    var ng = NamedGlobal.initStored(Value.initNumber(42));

    std.debug.assert(Value.initNumber(42).eql(try ng.get()));

    try ng.set(Value.initBoolean(true));

    std.debug.assert(Value.initBoolean(true).eql(try ng.get()));
}

test "NamedGlobal (referenced)" {
    var value = Value.initNumber(42);

    var ng = NamedGlobal.initReferenced(&value);

    std.debug.assert(value.eql(try ng.get()));

    try ng.set(Value.initBoolean(true));

    std.debug.assert(value.eql(Value.initBoolean(true)));
}

// test "NamedGlobal (smart)" {
//     var value = Value.initNumber(42);

//     const MySmarty = struct {
//         fn read(ctx: SmartGlobal.Context) Value {
//             return ctx.get(Value).*;
//         }

//         fn write(ctx: SmartGlobal.Context, val: Value) void {
//             ctx.get(Value).* = val;
//         }
//     };

//     var ng = NamedGlobal.initSmart(
//         SmartGlobal.initReadWrite(SmartGlobal.Context.init(Value, &value), MySmarty.read, MySmarty.write),
//     );

//     std.debug.assert(value.eql(try ng.get()));

//     try ng.set(Value.initBoolean(true));

//     std.debug.assert(value.eql(Value.initBoolean(true)));
// }
