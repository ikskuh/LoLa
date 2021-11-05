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

/// Installs the LoLa standard library into the given environment,
/// providing it with a basic set of functions.
/// `allocator` will be used to perform new allocations for the environment.
pub fn install(environment: *lola.runtime.Environment, allocator: *std.mem.Allocator) !void {
    try environment.installModule(@This(), lola.runtime.Context.make(*std.mem.Allocator, allocator));
}

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
    var pool = lola.runtime.ObjectPool([_]type{}).init(std.testing.allocator);
    defer pool.deinit();

    var env = try lola.runtime.Environment.init(std.testing.allocator, &empty_compile_unit, pool.interface());
    defer env.deinit();

    // TODO: Reinsert this
    try install(&env, std.testing.allocator);
}

pub fn Sleep(env: *lola.runtime.Environment, call_context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.AsyncFunctionCall {
    _ = env;

    const allocator = call_context.cast(*std.mem.Allocator);

    if (args.len != 1)
        return error.InvalidArgs;
    const seconds = try args[0].toNumber();

    const Context = struct {
        allocator: *std.mem.Allocator,
        end_time: f64,
    };

    const ptr = try allocator.create(Context);
    ptr.* = Context{
        .allocator = allocator,
        .end_time = @intToFloat(f64, milliTimestamp()) + 1000.0 * seconds,
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
            fn execute(exec_context: lola.runtime.Context) anyerror!?lola.runtime.Value {
                const ctx = exec_context.cast(*Context);

                if (ctx.end_time < @intToFloat(f64, milliTimestamp())) {
                    return .void;
                } else {
                    return null;
                }
            }
        }.execute,
    };
}

pub fn Yield(env: *lola.runtime.Environment, call_context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.AsyncFunctionCall {
    _ = env;

    const allocator = call_context.cast(*std.mem.Allocator);

    if (args.len != 0)
        return error.InvalidArgs;

    const Context = struct {
        allocator: *std.mem.Allocator,
        end: bool,
    };

    const ptr = try allocator.create(Context);
    ptr.* = Context{
        .allocator = allocator,
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
            fn execute(exec_context: lola.runtime.Context) anyerror!?lola.runtime.Value {
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

pub fn Length(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return switch (args[0]) {
        .string => |str| lola.runtime.Value.initNumber(@intToFloat(f64, str.contents.len)),
        .array => |arr| lola.runtime.Value.initNumber(@intToFloat(f64, arr.contents.len)),
        else => error.TypeMismatch,
    };
}

pub fn SubString(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
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
        return lola.runtime.Value.initString(allocator, "");

    const sliced = if (args.len == 3)
        str.contents[start..][0..std.math.min(str.contents.len - start, try args[2].toInteger(usize))]
    else
        str.contents[start..];

    return try lola.runtime.Value.initString(allocator, sliced);
}
pub fn Trim(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len != 1)
        return error.InvalidArgs;
    if (args[0] != .string)
        return error.TypeMismatch;
    const str = args[0].string;

    return try lola.runtime.Value.initString(
        allocator,
        std.mem.trim(u8, str.contents, &whitespace),
    );
}

pub fn TrimLeft(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len != 1)
        return error.InvalidArgs;
    if (args[0] != .string)
        return error.TypeMismatch;
    const str = args[0].string;

    return try lola.runtime.Value.initString(
        allocator,
        std.mem.trimLeft(u8, str.contents, &whitespace),
    );
}

pub fn TrimRight(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len != 1)
        return error.InvalidArgs;
    if (args[0] != .string)
        return error.TypeMismatch;
    const str = args[0].string;

    return try lola.runtime.Value.initString(
        allocator,
        std.mem.trimRight(u8, str.contents, &whitespace),
    );
}

pub fn IndexOf(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
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
            lola.runtime.Value.initNumber(@intToFloat(f64, index))
        else
            .void;
    } else if (args[0] == .array) {
        const haystack = args[0].array.contents;
        for (haystack) |val, i| {
            if (val.eql(args[1]))
                return lola.runtime.Value.initNumber(@intToFloat(f64, i));
        }
        return .void;
    } else {
        return error.TypeMismatch;
    }
}

pub fn LastIndexOf(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
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
            lola.runtime.Value.initNumber(@intToFloat(f64, index))
        else
            .void;
    } else if (args[0] == .array) {
        const haystack = args[0].array.contents;

        var i: usize = haystack.len;
        while (i > 0) {
            i -= 1;
            if (haystack[i].eql(args[1]))
                return lola.runtime.Value.initNumber(@intToFloat(f64, i));
        }
        return .void;
    } else {
        return error.TypeMismatch;
    }
}

pub fn Byte(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    if (args[0] != .string)
        return error.TypeMismatch;
    const value = args[0].string.contents;
    if (value.len > 0)
        return lola.runtime.Value.initNumber(@intToFloat(f64, value[0]))
    else
        return .void;
}

pub fn Chr(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len != 1)
        return error.InvalidArgs;
    const val = try args[0].toInteger(u8);

    return try lola.runtime.Value.initString(
        allocator,
        &[_]u8{val},
    );
}

pub fn NumToString(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len < 1 or args.len > 2)
        return error.InvalidArgs;
    var buffer: [256]u8 = undefined;

    const slice = if (args.len == 2) blk: {
        const base = try args[1].toInteger(u8);

        const val = try args[0].toInteger(isize);
        const len = std.fmt.formatIntBuf(&buffer, val, base, .upper, std.fmt.FormatOptions{});

        break :blk buffer[0..len];
    } else blk: {
        var stream = std.io.fixedBufferStream(&buffer);

        const val = try args[0].toNumber();
        try std.fmt.formatFloatDecimal(val, .{}, stream.writer());

        break :blk stream.getWritten();
    };
    return try lola.runtime.Value.initString(allocator, slice);
}

pub fn StringToNum(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
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

        return lola.runtime.Value.initNumber(@intToFloat(f64, val));
    } else {
        const val = std.fmt.parseFloat(f64, str) catch return .void;
        return lola.runtime.Value.initNumber(val);
    }
}

pub fn Split(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len < 2 or args.len > 3)
        return error.InvalidArgs;

    const input = try args[0].toString();
    const separator = try args[1].toString();
    const removeEmpty = if (args.len == 3) try args[2].toBoolean() else false;

    var items = std.ArrayList(lola.runtime.Value).init(allocator);
    defer {
        for (items.items) |*i| {
            i.deinit();
        }
        items.deinit();
    }

    var iter = std.mem.split(u8, input, separator);
    while (iter.next()) |slice| {
        if (!removeEmpty or slice.len > 0) {
            var val = try lola.runtime.Value.initString(allocator, slice);
            errdefer val.deinit();

            try items.append(val);
        }
    }

    return lola.runtime.Value.fromArray(lola.runtime.Array{
        .allocator = allocator,
        .contents = items.toOwnedSlice(),
    });
}

pub fn Join(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len < 1 or args.len > 2)
        return error.InvalidArgs;

    const array = try args[0].toArray();
    const separator = if (args.len == 2) try args[1].toString() else "";

    for (array.contents) |item| {
        if (item != .string)
            return error.TypeMismatch;
    }

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (array.contents) |item, i| {
        if (i > 0) {
            try result.appendSlice(separator);
        }
        try result.appendSlice(try item.toString());
    }

    return lola.runtime.Value.fromString(lola.runtime.String.initFromOwned(
        allocator,
        result.toOwnedSlice(),
    ));
}

pub fn Array(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len < 1 or args.len > 2)
        return error.InvalidArgs;

    const length = try args[0].toInteger(usize);
    const init_val = if (args.len > 1) args[1] else .void;

    var arr = try lola.runtime.Array.init(allocator, length);
    for (arr.contents) |*item| {
        item.* = try init_val.clone();
    }
    return lola.runtime.Value.fromArray(arr);
}

pub fn Range(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len < 1 or args.len > 2)
        return error.InvalidArgs;

    if (args.len == 2) {
        const start = try args[0].toInteger(usize);
        const length = try args[1].toInteger(usize);

        var arr = try lola.runtime.Array.init(allocator, length);
        for (arr.contents) |*item, i| {
            item.* = lola.runtime.Value.initNumber(@intToFloat(f64, start + i));
        }
        return lola.runtime.Value.fromArray(arr);
    } else {
        const length = try args[0].toInteger(usize);
        var arr = try lola.runtime.Array.init(allocator, length);
        for (arr.contents) |*item, i| {
            item.* = lola.runtime.Value.initNumber(@intToFloat(f64, i));
        }
        return lola.runtime.Value.fromArray(arr);
    }
}

pub fn Slice(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len != 3)
        return error.InvalidArgs;

    const array = try args[0].toArray();
    const start = try args[1].toInteger(usize);
    const length = try args[2].toInteger(usize);

    // Out of bounds
    if (start >= array.contents.len)
        return lola.runtime.Value.fromArray(try lola.runtime.Array.init(allocator, 0));

    const actual_length = std.math.min(length, array.contents.len - start);

    var arr = try lola.runtime.Array.init(allocator, actual_length);
    errdefer arr.deinit();

    for (arr.contents) |*item, i| {
        item.* = try array.contents[start + i].clone();
    }

    return lola.runtime.Value.fromArray(arr);
}

pub fn DeltaEqual(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 3)
        return error.InvalidArgs;
    const a = try args[0].toNumber();
    const b = try args[1].toNumber();
    const delta = try args[2].toNumber();
    return lola.runtime.Value.initBoolean(std.math.fabs(a - b) < delta);
}

pub fn Floor(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.Value.initNumber(std.math.floor(try args[0].toNumber()));
}

pub fn Ceiling(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.Value.initNumber(std.math.ceil(try args[0].toNumber()));
}

pub fn Round(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.Value.initNumber(std.math.round(try args[0].toNumber()));
}

pub fn Sin(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.Value.initNumber(std.math.sin(try args[0].toNumber()));
}

pub fn Cos(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.Value.initNumber(std.math.cos(try args[0].toNumber()));
}

pub fn Tan(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.Value.initNumber(std.math.tan(try args[0].toNumber()));
}

pub fn Atan(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len == 1) {
        return lola.runtime.Value.initNumber(
            std.math.atan(try args[0].toNumber()),
        );
    } else if (args.len == 2) {
        return lola.runtime.Value.initNumber(std.math.atan2(
            f64,
            try args[0].toNumber(),
            try args[1].toNumber(),
        ));
    } else {
        return error.InvalidArgs;
    }
}

pub fn Sqrt(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.Value.initNumber(std.math.sqrt(try args[0].toNumber()));
}

pub fn Pow(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 2)
        return error.InvalidArgs;
    return lola.runtime.Value.initNumber(std.math.pow(
        f64,
        try args[0].toNumber(),
        try args[1].toNumber(),
    ));
}

pub fn Log(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len == 1) {
        return lola.runtime.Value.initNumber(
            std.math.log10(try args[0].toNumber()),
        );
    } else if (args.len == 2) {
        return lola.runtime.Value.initNumber(std.math.log(
            f64,
            try args[1].toNumber(),
            try args[0].toNumber(),
        ));
    } else {
        return error.InvalidArgs;
    }
}

pub fn Exp(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.Value.initNumber(std.math.exp(try args[0].toNumber()));
}

pub fn Timestamp(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    _ = context;
    if (args.len != 0)
        return error.InvalidArgs;
    return lola.runtime.Value.initNumber(@intToFloat(f64, milliTimestamp()) / 1000.0);
}

pub fn TypeOf(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len != 1)
        return error.InvalidArgs;
    return lola.runtime.Value.initString(allocator, switch (args[0]) {
        .void => "void",
        .boolean => "boolean",
        .string => "string",
        .number => "number",
        .object => "object",
        .array => "array",
        .enumerator => "enumerator",
    });
}

pub fn ToString(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);

    if (args.len != 1)
        return error.InvalidArgs;

    var str = try std.fmt.allocPrint(allocator, "{}", .{args[0]});

    return lola.runtime.Value.fromString(lola.runtime.String.initFromOwned(allocator, str));
}

pub fn HasFunction(env: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = context;
    switch (args.len) {
        1 => {
            var name = try args[0].toString();
            return lola.runtime.Value.initBoolean(env.functions.get(name) != null);
        },
        2 => {
            var obj = try args[0].toObject();
            var name = try args[1].toString();

            const maybe_method = try env.objectPool.getMethod(obj, name);
            return lola.runtime.Value.initBoolean(maybe_method != null);
        },
        else => return error.InvalidArgs,
    }
}

pub fn Serialize(env: *lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len != 1)
        return error.InvalidArgs;

    const value = args[0];

    var string_buffer = std.ArrayList(u8).init(allocator);
    defer string_buffer.deinit();

    try value.serialize(string_buffer.writer());

    return lola.runtime.Value.fromString(lola.runtime.String.initFromOwned(allocator, string_buffer.toOwnedSlice()));
}

pub fn Deserialize(env: *lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
    _ = env;
    const allocator = context.cast(*std.mem.Allocator);
    if (args.len != 1)
        return error.InvalidArgs;

    const serialized_string = try args[0].toString();

    var stream = std.io.fixedBufferStream(serialized_string);

    return try lola.runtime.Value.deserialize(stream.reader(), allocator);
}

pub fn Random(env: *lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
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
        var held = random_mutex.acquire();
        defer held.release();

        if (random == null) {
            random = std.rand.DefaultPrng.init(@bitCast(u64, @intToFloat(f64, milliTimestamp())));
        }

        result = lower + (upper - lower) * random.?.random().float(f64);
    }

    return lola.runtime.Value.initNumber(result);
}

pub fn RandomInt(env: *lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) !lola.runtime.Value {
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
        var held = random_mutex.acquire();
        defer held.release();

        if (random == null) {
            random = std.rand.DefaultPrng.init(@bitCast(u64, @intToFloat(f64, milliTimestamp())));
        }

        result = random.?.random().intRangeLessThan(i32, lower, upper);
    }

    return lola.runtime.Value.initInteger(i32, result);
}

var random_mutex = std.Thread.Mutex{};
var random: ?std.rand.DefaultPrng = null;
