const std = @import("std");
const lola = @import("../main.zig");

const whitespace = [_]u8{
    0x09, // horizontal tab
    0x0A, // line feed
    0x0B, // vertical tab
    0x0C, // form feed
    0x0D, // carriage return
    0x20, // space
};

/// Installs the LoLa standard library into the given environment,
/// providing it with a basic set of functions.
/// `allocator` will be used to perform new allocations for the environment.
pub fn install(environment: *lola.Environment, allocator: *std.mem.Allocator) !void {
    // Install all functions from the namespace "functions":
    inline for (std.meta.declarations(sync_functions)) |decl| {
        try environment.installFunction(decl.name, lola.Function{
            .syncUser = lola.UserFunction{
                .context = lola.Context.init(std.mem.Allocator, allocator),
                .destructor = null,
                .call = @field(sync_functions, decl.name),
            },
        });
    }
    inline for (std.meta.declarations(async_functions)) |decl| {
        try environment.installFunction(decl.name, lola.Function{
            .asyncUser = lola.AsyncUserFunction{
                .context = lola.Context.init(std.mem.Allocator, allocator),
                .destructor = null,
                .call = @field(async_functions, decl.name),
            },
        });
    }

    try environment.addGlobal("Pi", lola.Value.initNumber(std.math.pi));
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
    var env = try lola.Environment.init(std.testing.allocator, &empty_compile_unit);
    defer env.deinit();

    // TODO: Reinsert this
    // try install(&env, std.testing.allocator);
}

const async_functions = struct {
    fn Sleep(call_context: lola.Context, args: []const lola.Value) anyerror!lola.AsyncFunctionCall {
        const allocator = call_context.get(std.mem.Allocator);

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
            .end_time = @intToFloat(f64, std.time.milliTimestamp()) + 1000.0 * seconds,
        };

        return lola.AsyncFunctionCall{
            .context = lola.Context.init(Context, ptr),
            .destructor = struct {
                fn dtor(exec_context: lola.Context) void {
                    const ctx = exec_context.get(Context);
                    ctx.allocator.destroy(ctx);
                }
            }.dtor,
            .execute = struct {
                fn execute(exec_context: lola.Context) anyerror!?lola.Value {
                    const ctx = exec_context.get(Context);

                    if (ctx.end_time < @intToFloat(f64, std.time.milliTimestamp())) {
                        return lola.Value.initVoid();
                    } else {
                        return null;
                    }
                }
            }.execute,
        };
    }
};

const sync_functions = struct {
    fn Length(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;
        return switch (args[0]) {
            .string => |str| lola.Value.initNumber(@intToFloat(f64, str.contents.len)),
            .array => |arr| lola.Value.initNumber(@intToFloat(f64, arr.contents.len)),
            else => error.TypeMismatch,
        };
    }

    fn SubString(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
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
            return lola.Value.initString(allocator, "");

        const sliced = if (args.len == 3)
            str.contents[start..][0..std.math.min(str.contents.len - start, try args[2].toInteger(usize))]
        else
            str.contents[start..];

        return try lola.Value.initString(allocator, sliced);
    }
    fn Trim(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;
        if (args[0] != .string)
            return error.TypeMismatch;
        const str = args[0].string;

        return try lola.Value.initString(
            allocator,
            std.mem.trim(u8, str.contents, &whitespace),
        );
    }

    fn TrimLeft(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;
        if (args[0] != .string)
            return error.TypeMismatch;
        const str = args[0].string;

        return try lola.Value.initString(
            allocator,
            std.mem.trimLeft(u8, str.contents, &whitespace),
        );
    }

    fn TrimRight(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;
        if (args[0] != .string)
            return error.TypeMismatch;
        const str = args[0].string;

        return try lola.Value.initString(
            allocator,
            std.mem.trimRight(u8, str.contents, &whitespace),
        );
    }

    fn IndexOf(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 2)
            return error.InvalidArgs;
        if (args[0] == .string) {
            if (args[1] != .string)
                return error.TypeMismatch;
            const haystack = args[0].string.contents;
            const needle = args[1].string.contents;

            return if (std.mem.indexOf(u8, haystack, needle)) |index|
                lola.Value.initNumber(@intToFloat(f64, index))
            else
                lola.Value.initVoid();
        } else if (args[0] == .array) {
            const haystack = args[0].array.contents;
            for (haystack) |val, i| {
                if (val.eql(args[1]))
                    return lola.Value.initNumber(@intToFloat(f64, i));
            }
            return lola.Value.initVoid();
        } else {
            return error.TypeMismatch;
        }
    }

    fn LastIndexOf(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 2)
            return error.InvalidArgs;
        if (args[0] == .string) {
            if (args[1] != .string)
                return error.TypeMismatch;
            const haystack = args[0].string.contents;
            const needle = args[1].string.contents;

            return if (std.mem.lastIndexOf(u8, haystack, needle)) |index|
                lola.Value.initNumber(@intToFloat(f64, index))
            else
                lola.Value.initVoid();
        } else if (args[0] == .array) {
            const haystack = args[0].array.contents;

            var i: usize = haystack.len;
            while (i > 0) {
                i -= 1;
                if (haystack[i].eql(args[1]))
                    return lola.Value.initNumber(@intToFloat(f64, i));
            }
            return lola.Value.initVoid();
        } else {
            return error.TypeMismatch;
        }
    }

    fn Byte(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;
        if (args[0] != .string)
            return error.TypeMismatch;
        const value = args[0].string.contents;
        if (value.len > 0)
            return lola.Value.initNumber(@intToFloat(f64, value[0]))
        else
            return lola.Value.initVoid();
    }

    fn Chr(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;
        const val = try args[0].toInteger(u8);

        return try lola.Value.initString(
            allocator,
            &[_]u8{val},
        );
    }

    fn NumToString(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len < 1 or args.len > 2)
            return error.InvalidArgs;
        var buffer: [256]u8 = undefined;

        const slice = if (args.len == 2) blk: {
            const base = try args[1].toInteger(u8);

            const val = try args[0].toInteger(isize);
            const len = std.fmt.formatIntBuf(&buffer, val, base, true, std.fmt.FormatOptions{});

            break :blk buffer[0..len];
        } else blk: {
            var stream = std.io.fixedBufferStream(&buffer);

            const val = try args[0].toNumber();
            try std.fmt.formatFloatDecimal(val, .{}, stream.writer());

            break :blk stream.getWritten();
        };
        return try lola.Value.initString(allocator, slice);
    }

    fn StringToNum(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len < 1 or args.len > 2)
            return error.InvalidArgs;
        if (args[0] != .string)
            return error.TypeMismatch;
        const str = args[0].string.contents;

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

            const val = try std.fmt.parseInt(isize, text, base); // return lola.Value.initVoid();

            return lola.Value.initNumber(@intToFloat(f64, val));
        } else {
            const val = std.fmt.parseFloat(f64, str) catch return lola.Value.initVoid();
            return lola.Value.initNumber(val);
        }
    }

    fn Range(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len < 1 or args.len > 2)
            return error.InvalidArgs;

        if (args.len == 2) {
            const start = try args[0].toInteger(usize);
            const length = try args[1].toInteger(usize);

            var arr = try lola.Array.init(allocator, length);
            for (arr.contents) |*item, i| {
                item.* = lola.Value.initNumber(@intToFloat(f64, start + i));
            }
            return lola.Value.fromArray(arr);
        } else {
            const length = try args[0].toInteger(usize);
            var arr = try lola.Array.init(allocator, length);
            for (arr.contents) |*item, i| {
                item.* = lola.Value.initNumber(@intToFloat(f64, i));
            }
            return lola.Value.fromArray(arr);
        }
    }

    fn Slice(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 3)
            return error.InvalidArgs;

        const array = try args[0].toArray();
        const start = try args[1].toInteger(usize);
        const length = try args[2].toInteger(usize);

        // Out of bounds
        if (start >= array.contents.len)
            return lola.Value.fromArray(try lola.Array.init(allocator, 0));

        const actual_length = std.math.min(length, array.contents.len - start);

        var arr = try lola.Array.init(allocator, actual_length);
        errdefer arr.deinit();

        for (arr.contents) |*item, i| {
            item.* = try array.contents[start + i].clone();
        }

        return lola.Value.fromArray(arr);
    }

    fn DeltaEqual(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 3)
            return error.InvalidArgs;
        const a = try args[0].toNumber();
        const b = try args[1].toNumber();
        const delta = try args[2].toNumber();
        return lola.Value.initBoolean(std.math.fabs(a - b) < delta);
    }

    fn Sin(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;
        return lola.Value.initNumber(std.math.sin(try args[0].toNumber()));
    }

    fn Cos(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;
        return lola.Value.initNumber(std.math.cos(try args[0].toNumber()));
    }

    fn Tan(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;
        return lola.Value.initNumber(std.math.tan(try args[0].toNumber()));
    }

    fn Atan(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len == 1) {
            return lola.Value.initNumber(
                std.math.atan(try args[0].toNumber()),
            );
        } else if (args.len == 2) {
            return lola.Value.initNumber(std.math.atan2(
                f64,
                try args[0].toNumber(),
                try args[1].toNumber(),
            ));
        } else {
            return error.InvalidArgs;
        }
    }

    fn Sqrt(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;
        return lola.Value.initNumber(std.math.sqrt(try args[0].toNumber()));
    }

    fn Pow(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 2)
            return error.InvalidArgs;
        return lola.Value.initNumber(std.math.pow(
            f64,
            try args[0].toNumber(),
            try args[1].toNumber(),
        ));
    }

    fn Log(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len == 1) {
            return lola.Value.initNumber(
                std.math.log10(try args[0].toNumber()),
            );
        } else if (args.len == 2) {
            return lola.Value.initNumber(std.math.log(
                f64,
                try args[1].toNumber(),
                try args[0].toNumber(),
            ));
        } else {
            return error.InvalidArgs;
        }
    }

    fn Exp(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;
        return lola.Value.initNumber(std.math.exp(try args[0].toNumber()));
    }

    fn Timestamp(context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 0)
            return error.InvalidArgs;
        return lola.Value.initNumber(@intToFloat(f64, std.time.milliTimestamp()) / 1000.0);
    }

    fn TypeOf(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;
        return lola.Value.initString(allocator, switch (args[0]) {
            .void => "void",
            .boolean => "boolean",
            .string => "string",
            .number => "number",
            .object => "object",
            .array => "array",
            .enumerator => "enumerator",
        });
    }

    fn ToString(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;

        var str = try std.fmt.allocPrint(allocator, "{}", .{args[0]});

        return lola.Value.fromString(lola.String.initFromOwned(allocator, str));
    }

    fn HasFunction(env: *lola.Environment, context: lola.Context, args: []const lola.Value) !lola.Value {
        const allocator = context.get(std.mem.Allocator);
        switch (args.len) {
            1 => {
                var name = try args[0].toString();
                return lola.Value.initBoolean(env.functions.get(name) != null);
            },
            2 => {
                var obj = try args[0].toObject();
                var name = try args[1].toString();

                if (!env.objectPool.isObjectValid(obj))
                    return error.InvalidObject;

                return lola.Value.initBoolean(env.objectPool.getMethod(obj, name) != null);
            },
            else => return error.InvalidArgs,
        }
    }
};
