// This file implements the LoLa standard library

const std = @import("std");
const builtin = @import("builtin");
const lola = @import("../main.zig");

const whitespace = [_]u8{
    0x09, // horizontal tab
    0x0A, // line feed
    0x0B, // vertical tab
    0x0C, // form feed
    0x0D, // carriage return
    0x20, // space
};

const root = @import("root");

const milliTimestamp = if (builtin.os.tag == .freestanding)
    if (@hasDecl(root, "milliTimestamp"))
        root.milliTimestamp
    else
        @compileError("Please provide milliTimestamp in the root file for freestanding targets!")
else
    std.time.milliTimestamp;

/// empty compile unit for testing purposes
const empty_compile_unit = lola.CompileUnit{
    .arena = std.heap.ArenaAllocator.init(std.testing.failing_allocator),
    .comment = "empty compile unit",
    .globalCount = 0,
    .temporaryCount = 0,
    .code = "",
    .functions = &[0]lola.CompileUnit.Function{},
    .debugSymbols = &[0]lola.CompileUnit.DebugSymbol{},
};

test "stdlib.install" {
    var pool = lola.runtime.objects.ObjectPool([_]type{}).init(std.testing.allocator);
    defer pool.deinit();

    var env = try lola.runtime.Environment.init(std.testing.allocator, &empty_compile_unit, pool.interface());
    defer env.deinit();

    // TODO: Reinsert this
    try env.installModule(@This(), lola.runtime.Context.null_pointer);
}

pub fn Sleep(env: *lola.runtime.Environment, call_context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.AsyncFunctionCall {
    _ = call_context;

    if (args.len != 1)
        return error.InvalidArgs;
    const seconds = try args[0].toNumber();

    const Context = struct {
        allocator: std.mem.Allocator,
        end_time: f64,
    };

    const ptr = try env.allocator.create(Context);
    ptr.* = Context{
        .allocator = env.allocator,
        .end_time = @as(f64, @floatFromInt(milliTimestamp())) + 1000.0 * seconds,
    };

    return lola.runtime.AsyncFunctionCall{
        .context = lola.runtime.Context.make(*Context, ptr),
        .destructor = struct {
            fn dtor(exec_context: lola.runtime.Context) void {
                const ctx = exec_context.cast(*Context);
                ctx.allocator.destroy(ctx);
            }
        }.dtor,
        .execute = struct {
            fn execute(exec_context: lola.runtime.Context) anyerror!?lola.runtime.value.Value {
                const ctx = exec_context.cast(*Context);

                if (ctx.end_time < @as(f64, @floatFromInt(milliTimestamp()))) {
                    return .void;
                } else {
                    return null;
                }
            }
        }.execute,
    };
}

pub fn Yield(env: *lola.runtime.Environment, call_context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.AsyncFunctionCall {
    _ = call_context;

    if (args.len != 0)
        return error.InvalidArgs;

    const Context = struct {
        allocator: std.mem.Allocator,
        end: bool,
    };

    const ptr = try env.allocator.create(Context);
    ptr.* = Context{
        .allocator = env.allocator,
        .end = false,
    };

    return lola.runtime.AsyncFunctionCall{
        .context = lola.runtime.Context.make(*Context, ptr),
        .destructor = struct {
            fn dtor(exec_context: lola.runtime.Context) void {
                const ctx = exec_context.cast(*Context);
                ctx.allocator.destroy(ctx);
            }
        }.dtor,
        .execute = struct {
            fn execute(exec_context: lola.runtime.Context) anyerror!?lola.runtime.value.Value {
                const ctx = exec_context.cast(*Context);

                if (ctx.end) {
                    return .void;
                } else {
                    ctx.end = true;
                    return null;
                }
            }
        }.execute,
    };
}

pub fn Length(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return switch (args[0]) {
        .string => |str| lola.runtime.value.Value.initNumber(@as(f64, @floatFromInt(str.contents.len))),
        .array => |arr| lola.runtime.value.Value.initNumber(@as(f64, @floatFromInt(arr.contents.len))),
        else => error.TypeMismatch,
    };
}

pub fn SubString(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len < 2 or args.len > 3)
        return error.InvalidArgs;
    if (args[0] != .string)
        return error.TypeMismatch;
    if (args[1] != .number)
        return error.TypeMismatch;
    if (args.len == 3 and args[2] != .number)
        return error.TypeMismatch;

    const str = args[0].string;
    const start = try args[1].toInteger(usize);
    if (start >= str.contents.len)
        return lola.runtime.value.Value.initString(env.allocator, "");

    const sliced = if (args.len == 3)
        str.contents[start..][0..@min(str.contents.len - start, try args[2].toInteger(usize))]
    else
        str.contents[start..];

    return try lola.runtime.value.Value.initString(env.allocator, sliced);
}
pub fn Trim(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    if (args[0] != .string)
        return error.TypeMismatch;
    const str = args[0].string;

    return try lola.runtime.value.Value.initString(
        env.allocator,
        std.mem.trim(u8, str.contents, &whitespace),
    );
}

pub fn TrimLeft(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    if (args[0] != .string)
        return error.TypeMismatch;
    const str = args[0].string;

    return try lola.runtime.value.Value.initString(
        env.allocator,
        std.mem.trimLeft(u8, str.contents, &whitespace),
    );
}

pub fn TrimRight(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    if (args[0] != .string)
        return error.TypeMismatch;
    const str = args[0].string;

    return try lola.runtime.value.Value.initString(
        env.allocator,
        std.mem.trimRight(u8, str.contents, &whitespace),
    );
}

pub fn IndexOf(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 2)
        return error.InvalidArgs;
    if (args[0] == .string) {
        if (args[1] != .string)
            return error.TypeMismatch;
        const haystack = args[0].string.contents;
        const needle = args[1].string.contents;

        return if (std.mem.indexOf(u8, haystack, needle)) |index|
            lola.runtime.value.Value.initNumber(@as(f64, @floatFromInt(index)))
        else
            .void;
    } else if (args[0] == .array) {
        const haystack = args[0].array.contents;
        for (haystack, 0..) |val, i| {
            if (val.eql(args[1]))
                return lola.runtime.value.Value.initNumber(@as(f64, @floatFromInt(i)));
        }
        return .void;
    } else {
        return error.TypeMismatch;
    }
}

pub fn LastIndexOf(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 2)
        return error.InvalidArgs;
    if (args[0] == .string) {
        if (args[1] != .string)
            return error.TypeMismatch;
        const haystack = args[0].string.contents;
        const needle = args[1].string.contents;

        return if (std.mem.lastIndexOf(u8, haystack, needle)) |index|
            lola.runtime.value.Value.initNumber(@as(f64, @floatFromInt(index)))
        else
            .void;
    } else if (args[0] == .array) {
        const haystack = args[0].array.contents;

        var i: usize = haystack.len;
        while (i > 0) {
            i -= 1;
            if (haystack[i].eql(args[1]))
                return lola.runtime.value.Value.initNumber(@as(f64, @floatFromInt(i)));
        }
        return .void;
    } else {
        return error.TypeMismatch;
    }
}

pub fn Byte(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    if (args[0] != .string)
        return error.TypeMismatch;
    const value = args[0].string.contents;
    if (value.len > 0)
        return lola.runtime.value.Value.initNumber(@as(f64, @floatFromInt(value[0])))
    else
        return .void;
}

pub fn Chr(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    const val = try args[0].toInteger(u8);

    return try lola.runtime.value.Value.initString(
        env.allocator,
        &[_]u8{val},
    );
}

/// std.Io.Writer wrapper to count how many bytes were written
const WriterCounter = struct {
    const Self = @This();
    /// number of bytes written to stream
    count: usize = 0,
    interface: std.Io.Writer,
    old_vtable: *const std.Io.Writer.VTable,
    fn drain_wrapper(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const counter: *Self = @alignCast(@fieldParentPtr("interface", w));
        const old_fn = counter.old_vtable.drain;
        counter.count += try old_fn(w, data, splat);
        return counter.count;
    }
    pub fn init(old_writer: std.Io.Writer) Self {
        var interface = old_writer;
        const old_vtable = interface.vtable;
        interface.vtable = &std.Io.Writer.VTable{
            .drain = drain_wrapper,
            .flush = old_vtable.flush,
            .rebase = old_vtable.rebase,
            .sendFile = old_vtable.sendFile,
        };
        return Self{
            .interface = interface,
            .old_vtable = old_vtable,
        };
    }
    pub fn getWritten(self: *const Self) usize {
        return self.count;
    }
};

pub fn NumToString(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len < 1 or args.len > 2)
        return error.InvalidArgs;
    var buffer: [256]u8 = undefined;
    var counter = WriterCounter.init(std.Io.Writer.fixed(&buffer));
    const stream = &counter.interface;

    const slice = if (args.len == 2) blk: {
        const base = try args[1].toInteger(u8);

        const val = try args[0].toInteger(isize);
        try stream.printInt(val, base, .upper, .{});
        const len = counter.getWritten();

        break :blk buffer[0..len];
    } else blk: {
        const val = try args[0].toNumber();

        try stream.print("{d}", .{val});
        const len = counter.getWritten();

        break :blk buffer[0..len];
    };
    return try lola.runtime.value.Value.initString(env.allocator, slice);
}

pub fn StringToNum(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len < 1 or args.len > 2)
        return error.InvalidArgs;
    const str = try args[0].toString();

    if (args.len == 2) {
        const base = try args[1].toInteger(u8);

        const text = if (base == 16) blk: {
            var tmp = str;
            if (std.mem.startsWith(u8, tmp, "0x"))
                tmp = tmp[2..];
            if (std.mem.endsWith(u8, tmp, "h"))
                tmp = tmp[0 .. tmp.len - 1];
            break :blk tmp;
        } else str;

        const val = try std.fmt.parseInt(isize, text, base); // return .void;

        return lola.runtime.value.Value.initNumber(@as(f64, @floatFromInt(val)));
    } else {
        const val = std.fmt.parseFloat(f64, str) catch return .void;
        return lola.runtime.value.Value.initNumber(val);
    }
}

pub fn Split(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len < 2 or args.len > 3)
        return error.InvalidArgs;

    const input = try args[0].toString();
    const separator = try args[1].toString();
    const removeEmpty = if (args.len == 3) try args[2].toBoolean() else false;

    var items = std.ArrayList(lola.runtime.value.Value).empty;
    defer {
        for (items.items) |*i| {
            i.deinit();
        }
        items.deinit(env.allocator);
    }

    var iter = std.mem.splitAny(u8, input, separator);
    while (iter.next()) |slice| {
        if (!removeEmpty or slice.len > 0) {
            var val = try lola.runtime.value.Value.initString(env.allocator, slice);
            errdefer val.deinit();

            try items.append(env.allocator, val);
        }
    }

    return lola.runtime.value.Value.fromArray(lola.runtime.value.Array{
        .allocator = env.allocator,
        .contents = try items.toOwnedSlice(env.allocator),
    });
}

pub fn Join(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len < 1 or args.len > 2)
        return error.InvalidArgs;

    const array = try args[0].toArray();
    const separator: []const u8 = if (args.len == 2) try args[1].toString() else "";

    for (array.contents) |item| {
        if (item != .string)
            return error.TypeMismatch;
    }

    var result = std.ArrayList(u8).empty;
    defer result.deinit(env.allocator);

    for (array.contents, 0..) |item, i| {
        if (i > 0) {
            try result.appendSlice(env.allocator, separator);
        }
        try result.appendSlice(env.allocator, try item.toString());
    }

    return lola.runtime.value.Value.fromString(lola.runtime.value.String.initFromOwned(
        env.allocator,
        try result.toOwnedSlice(env.allocator),
    ));
}

pub fn Array(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len < 1 or args.len > 2)
        return error.InvalidArgs;

    const length = try args[0].toInteger(usize);
    const init_val = if (args.len > 1) args[1] else .void;

    const arr = try lola.runtime.value.Array.init(env.allocator, length);
    for (arr.contents) |*item| {
        item.* = try init_val.clone();
    }
    return lola.runtime.value.Value.fromArray(arr);
}

pub fn Range(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len < 1 or args.len > 2)
        return error.InvalidArgs;

    if (args.len == 2) {
        const start = try args[0].toInteger(usize);
        const length = try args[1].toInteger(usize);

        const arr = try lola.runtime.value.Array.init(env.allocator, length);
        for (arr.contents, 0..) |*item, i| {
            item.* = lola.runtime.value.Value.initNumber(@as(f64, @floatFromInt(start + i)));
        }
        return lola.runtime.value.Value.fromArray(arr);
    } else {
        const length = try args[0].toInteger(usize);
        const arr = try lola.runtime.value.Array.init(env.allocator, length);
        for (arr.contents, 0..) |*item, i| {
            item.* = lola.runtime.value.Value.initNumber(@as(f64, @floatFromInt(i)));
        }
        return lola.runtime.value.Value.fromArray(arr);
    }
}

pub fn Slice(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len != 3)
        return error.InvalidArgs;

    const array = try args[0].toArray();
    const start = try args[1].toInteger(usize);
    const length = try args[2].toInteger(usize);

    // Out of bounds
    if (start >= array.contents.len)
        return lola.runtime.value.Value.fromArray(try lola.runtime.value.Array.init(env.allocator, 0));

    const actual_length = @min(length, array.contents.len - start);

    var arr = try lola.runtime.value.Array.init(env.allocator, actual_length);
    errdefer arr.deinit();

    for (arr.contents, 0..) |*item, i| {
        item.* = try array.contents[start + i].clone();
    }

    return lola.runtime.value.Value.fromArray(arr);
}

pub fn DeltaEqual(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 3)
        return error.InvalidArgs;
    const a = try args[0].toNumber();
    const b = try args[1].toNumber();
    const delta = try args[2].toNumber();
    return lola.runtime.value.Value.initBoolean(@abs(a - b) < delta);
}

pub fn Floor(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.value.Value.initNumber(@floor(try args[0].toNumber()));
}

pub fn Ceiling(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.value.Value.initNumber(@ceil(try args[0].toNumber()));
}

pub fn Round(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.value.Value.initNumber(@round(try args[0].toNumber()));
}

pub fn Sin(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.value.Value.initNumber(@sin(try args[0].toNumber()));
}

pub fn Cos(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.value.Value.initNumber(@cos(try args[0].toNumber()));
}

pub fn Tan(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.value.Value.initNumber(@tan(try args[0].toNumber()));
}

pub fn Atan(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len == 1) {
        return lola.runtime.value.Value.initNumber(
            std.math.atan(try args[0].toNumber()),
        );
    } else if (args.len == 2) {
        return lola.runtime.value.Value.initNumber(std.math.atan2(
            try args[0].toNumber(),
            try args[1].toNumber(),
        ));
    } else {
        return error.InvalidArgs;
    }
}

pub fn Sqrt(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.value.Value.initNumber(std.math.sqrt(try args[0].toNumber()));
}

pub fn Pow(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 2)
        return error.InvalidArgs;
    return lola.runtime.value.Value.initNumber(std.math.pow(
        f64,
        try args[0].toNumber(),
        try args[1].toNumber(),
    ));
}

pub fn Log(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len == 1) {
        return lola.runtime.value.Value.initNumber(
            std.math.log10(try args[0].toNumber()),
        );
    } else if (args.len == 2) {
        return lola.runtime.value.Value.initNumber(std.math.log(
            f64,
            try args[1].toNumber(),
            try args[0].toNumber(),
        ));
    } else {
        return error.InvalidArgs;
    }
}

pub fn Exp(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.value.Value.initNumber(@exp(try args[0].toNumber()));
}

pub fn Timestamp(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = env;
    _ = context;
    if (args.len != 0)
        return error.InvalidArgs;
    return lola.runtime.value.Value.initNumber(@as(f64, @floatFromInt(milliTimestamp())) / 1000.0);
}

pub fn TypeOf(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.value.Value.initString(env.allocator, switch (args[0]) {
        .void => "void",
        .boolean => "boolean",
        .string => "string",
        .number => "number",
        .object => "object",
        .array => "array",
        .enumerator => "enumerator",
    });
}

pub fn ToString(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;

    if (args.len != 1)
        return error.InvalidArgs;

    const str = try std.fmt.allocPrint(env.allocator, "{f}", .{args[0]});

    return lola.runtime.value.Value.fromString(lola.runtime.value.String.initFromOwned(env.allocator, str));
}

pub fn HasFunction(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    switch (args.len) {
        1 => {
            const name = try args[0].toString();
            return lola.runtime.value.Value.initBoolean(env.functions.get(name) != null);
        },
        2 => {
            const obj = try args[0].toObject();
            const name = try args[1].toString();

            const maybe_method = try env.objectPool.getMethod(obj, name);

            return lola.runtime.value.Value.initBoolean(maybe_method != null);
        },
        else => return error.InvalidArgs,
    }
}

pub fn Serialize(env: *lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;

    const value = args[0];

    var string_buffer = std.Io.Writer.Allocating.init(env.allocator);
    defer string_buffer.deinit();

    try value.serialize(&string_buffer.writer);

    return lola.runtime.value.Value.fromString(lola.runtime.value.String.initFromOwned(env.allocator, try string_buffer.toOwnedSlice()));
}

pub fn Deserialize(env: *lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;

    const serialized_string = try args[0].toString();

    var stream = std.io.Reader.fixed(serialized_string);

    return try lola.runtime.value.Value.deserialize(&stream, env.allocator);
}

pub fn Random(env: *lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    _ = env;

    var lower: f64 = 0;
    var upper: f64 = 1;

    switch (args.len) {
        0 => {},
        1 => upper = try args[0].toNumber(),
        2 => {
            lower = try args[0].toNumber();
            upper = try args[1].toNumber();
        },
        else => return error.InvalidArgs,
    }

    var result: f64 = undefined;
    {
        random_mutex.lock();
        defer random_mutex.unlock();

        if (random == null) {
            random = std.Random.DefaultPrng.init(@as(u64, @bitCast(@as(f64, @floatFromInt(milliTimestamp())))));
        }

        result = lower + (upper - lower) * random.?.random().float(f64);
    }

    return lola.runtime.value.Value.initNumber(result);
}

pub fn RandomInt(env: *lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) !lola.runtime.value.Value {
    _ = context;
    _ = env;

    var lower: i32 = 0;
    var upper: i32 = std.math.maxInt(i32);

    switch (args.len) {
        0 => {},
        1 => upper = try args[0].toInteger(i32),
        2 => {
            lower = try args[0].toInteger(i32);
            upper = try args[1].toInteger(i32);
        },
        else => return error.InvalidArgs,
    }

    var result: i32 = undefined;
    {
        random_mutex.lock();
        defer random_mutex.unlock();

        if (random == null) {
            random = std.Random.DefaultPrng.init(@as(u64, @bitCast(@as(f64, @floatFromInt(milliTimestamp())))));
        }

        result = random.?.random().intRangeLessThan(i32, lower, upper);
    }

    return lola.runtime.value.Value.initInteger(i32, result);
}

var random_mutex = std.Thread.Mutex{};
var random: ?std.Random.DefaultPrng = null;
