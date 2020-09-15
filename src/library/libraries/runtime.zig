// This file implements the LoLa Runtime Library.

const std = @import("std");
const lola = @import("../main.zig");
const root = @import("root");

const GlobalObjectPool = if (std.builtin.is_test)
// we need to do a workaround here for testing purposes
    lola.runtime.ObjectPool([_]type{
        LoLaList,
        LoLaDictionary,
    })
else if (@hasDecl(root, "ObjectPool"))
    root.ObjectPool
else
    @compileError("Please define and use a global ObjectPool type to use the runtime classes.");

comptime {
    if (std.builtin.is_test) {
        const T = lola.runtime.ObjectPool([_]type{
            LoLaList,
            LoLaDictionary,
        });

        if (!T.serializable)
            @compileError("Both LoLaList and LoLaDictionary must be serializable!");
    }
}

/// Installs the LoLa standard library into the given environment,
/// providing it with a basic set of functions.
/// `allocator` will be used to perform new allocations for the environment.
pub fn install(environment: *lola.runtime.Environment, allocator: *std.mem.Allocator) !void {
    // Install all functions from the namespace "functions":
    inline for (std.meta.declarations(sync_functions)) |decl| {
        try environment.installFunction(decl.name, lola.runtime.Function{
            .syncUser = lola.runtime.UserFunction{
                .context = lola.runtime.Context.init(std.mem.Allocator, allocator),
                .destructor = null,
                .call = @field(sync_functions, decl.name),
            },
        });
    }
    inline for (std.meta.declarations(async_functions)) |decl| {
        try environment.installFunction(decl.name, lola.runtime.Function{
            .asyncUser = lola.runtime.AsyncUserFunction{
                .context = lola.runtime.Context.init(std.mem.Allocator, allocator),
                .destructor = null,
                .call = @field(async_functions, decl.name),
            },
        });
    }
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

test "runtime.install" {
    var pool = GlobalObjectPool.init(std.testing.allocator);
    defer pool.deinit();

    var env = try lola.runtime.Environment.init(std.testing.allocator, &empty_compile_unit, pool.interface());
    defer env.deinit();

    try install(&env, std.testing.allocator);
}

const async_functions = struct {
    // fn Sleep(call_context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.AsyncFunctionCall {
    //     const allocator = call_context.get(std.mem.Allocator);

    //     if (args.len != 1)
    //         return error.InvalidArgs;
    //     const seconds = try args[0].toNumber();

    //     const Context = struct {
    //         allocator: *std.mem.Allocator,
    //         end_time: f64,
    //     };

    //     const ptr = try allocator.create(Context);
    //     ptr.* = Context{
    //         .allocator = allocator,
    //         .end_time = @intToFloat(f64, std.time.milliTimestamp()) + 1000.0 * seconds,
    //     };

    //     return lola.runtime.AsyncFunctionCall{
    //         .context = lola.runtime.Context.init(Context, ptr),
    //         .destructor = struct {
    //             fn dtor(exec_context: lola.runtime.Context) void {
    //                 const ctx = exec_context.get(Context);
    //                 ctx.allocator.destroy(ctx);
    //             }
    //         }.dtor,
    //         .execute = struct {
    //             fn execute(exec_context: lola.runtime.Context) anyerror!?lola.runtime.Value {
    //                 const ctx = exec_context.get(Context);

    //                 if (ctx.end_time < @intToFloat(f64, std.time.milliTimestamp())) {
    //                     return .void;
    //                 } else {
    //                     return null;
    //                 }
    //             }
    //         }.execute,
    //     };
    // }
};

const sync_functions = struct {
    fn Print(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
        const allocator = context.get(std.mem.Allocator);
        var stdout = std.io.getStdOut().writer();
        for (args) |value, i| {
            switch (value) {
                .string => |str| try stdout.writeAll(str.contents),
                else => try stdout.print("{}", .{value}),
            }
        }
        try stdout.writeAll("\n");
        return .void;
    }

    fn Exit(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
        if (args.len != 1)
            return error.InvalidArgs;

        const status = try args[0].toInteger(u8);
        std.process.exit(status);
    }

    fn ReadFile(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;

        const path = try args[0].toString();

        var file = std.fs.cwd().openFile(path, .{ .read = true, .write = false }) catch return .void;
        defer file.close();

        // 2 GB
        var contents = try file.reader().readAllAlloc(allocator, 2 << 30);

        return lola.runtime.Value.fromString(lola.runtime.String.initFromOwned(allocator, contents));
    }

    fn FileExists(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;

        const path = try args[0].toString();

        var file = std.fs.cwd().openFile(path, .{ .read = true, .write = false }) catch return lola.runtime.Value.initBoolean(false);
        file.close();

        return lola.runtime.Value.initBoolean(true);
    }

    fn WriteFile(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 2)
            return error.InvalidArgs;

        const path = try args[0].toString();
        const value = try args[1].toString();

        var file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(value);

        return .void;
    }

    fn CreateList(environment: *lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
        const allocator = context.get(std.mem.Allocator);

        if (args.len > 1)
            return error.InvalidArgs;

        if (args.len > 0) _ = try args[0].toArray();

        const list = try allocator.create(LoLaList);
        errdefer allocator.destroy(list);

        list.* = LoLaList{
            .allocator = allocator,
            .data = std.ArrayList(lola.runtime.Value).init(allocator),
        };

        if (args.len > 0) {
            const array = args[0].toArray() catch unreachable;

            errdefer list.data.deinit();
            try list.data.resize(array.contents.len);

            for (list.data.items) |*item| {
                item.* = .void;
            }

            errdefer for (list.data.items) |*item| {
                item.deinit();
            };
            for (list.data.items) |*item, index| {
                item.* = try array.contents[index].clone();
            }
        }

        return lola.runtime.Value.initObject(
            try environment.objectPool.castTo(GlobalObjectPool).createObject(list),
        );
    }

    fn CreateDictionary(environment: *lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 0)
            return error.InvalidArgs;

        const list = try allocator.create(LoLaDictionary);
        errdefer allocator.destroy(list);

        list.* = LoLaDictionary{
            .allocator = allocator,
            .data = std.ArrayList(LoLaDictionary.KV).init(allocator),
        };

        return lola.runtime.Value.initObject(
            try environment.objectPool.castTo(GlobalObjectPool).createObject(list),
        );
    }
};

pub const LoLaList = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    data: std.ArrayList(lola.runtime.Value),

    pub fn getMethod(self: *Self, name: []const u8) ?lola.runtime.Function {
        inline for (std.meta.declarations(funcs)) |decl| {
            if (std.mem.eql(u8, name, decl.name)) {
                return lola.runtime.Function{
                    .syncUser = .{
                        .context = lola.runtime.Context.init(Self, self),
                        .call = @field(funcs, decl.name),
                        .destructor = null,
                    },
                };
            }
        }
        return null;
    }

    pub fn destroyObject(self: *Self) void {
        for (self.data.items) |*item| {
            item.deinit();
        }
        self.data.deinit();
        self.allocator.destroy(self);
    }

    pub fn serializeObject(writer: lola.runtime.OutputStream.Writer, object: *Self) !void {
        try writer.writeIntLittle(u32, @intCast(u32, object.data.items.len));
        for (object.data.items) |item| {
            try item.serialize(writer);
        }
    }

    pub fn deserializeObject(allocator: *std.mem.Allocator, reader: lola.runtime.InputStream.Reader) !*Self {
        const item_count = try reader.readIntLittle(u32);
        var list = try allocator.create(Self);
        list.* = Self{
            .allocator = allocator,
            .data = std.ArrayList(lola.runtime.Value).init(allocator),
        };
        errdefer list.destroyObject(); // this will also free memory!

        try list.data.resize(item_count);

        // sane init to make destroyObject not explode
        // (deinit a void value is a no-op)
        for (list.data.items) |*item| {
            item.* = .void;
        }

        for (list.data.items) |*item| {
            item.* = try lola.runtime.Value.deserialize(reader, allocator);
        }

        return list;
    }

    const funcs = struct {
        fn Add(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const list = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;

            var cloned = try args[0].clone();
            errdefer cloned.deinit();

            try list.data.append(cloned);

            return .void;
        }

        fn Remove(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const list = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;

            const value = args[0];

            var src_index: usize = 0;
            var dst_index: usize = 0;
            while (src_index < list.data.items.len) : (src_index += 1) {
                const eql = list.data.items[src_index].eql(value);
                if (eql) {
                    // When the element is equal, we destroy and remove it.
                    // std.debug.print("deinit {} ({})\n", .{
                    //     src_index,
                    //     list.data.items[src_index],
                    // });
                    list.data.items[src_index].deinit();
                } else {
                    // Otherwise, we move the object to the front of the list skipping
                    // the already removed elements.
                    // std.debug.print("move {} ({}) → {} ({})\n", .{
                    //     src_index,
                    //     list.data.items[src_index],
                    //     dst_index,
                    //     list.data.items[dst_index],
                    // });
                    if (src_index > dst_index) {
                        list.data.items[dst_index] = list.data.items[src_index];
                    }
                    dst_index += 1;
                }
            }
            // note:
            // we don't need to deinit() excess values here as we moved them
            // above, so they are "twice" in the list.
            list.data.shrink(dst_index);

            return .void;
        }

        fn RemoveAt(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const list = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;

            const index = try args[0].toInteger(usize);

            if (index < list.data.items.len) {
                list.data.items[index].deinit();
                std.mem.copy(
                    lola.runtime.Value,
                    list.data.items[index..],
                    list.data.items[index + 1 ..],
                );
                list.data.shrink(list.data.items.len - 1);
            }

            return .void;
        }

        fn GetCount(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const list = context.get(Self);
            if (args.len != 0)
                return error.InvalidArgs;
            return lola.runtime.Value.initInteger(usize, list.data.items.len);
        }

        fn GetItem(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const list = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;
            const index = try args[0].toInteger(usize);
            if (index >= list.data.items.len)
                return error.OutOfRange;

            return try list.data.items[index].clone();
        }

        fn SetItem(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const list = context.get(Self);
            if (args.len != 2)
                return error.InvalidArgs;
            const index = try args[0].toInteger(usize);
            if (index >= list.data.items.len)
                return error.OutOfRange;

            var cloned = try args[1].clone();

            list.data.items[index].replaceWith(cloned);

            return .void;
        }

        fn ToArray(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const list = context.get(Self);
            if (args.len != 0)
                return error.InvalidArgs;

            var array = try lola.runtime.Array.init(list.allocator, list.data.items.len);
            errdefer array.deinit();

            for (array.contents) |*item, index| {
                item.* = try list.data.items[index].clone();
            }

            return lola.runtime.Value.fromArray(array);
        }

        fn IndexOf(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const list = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;

            for (list.data.items) |item, index| {
                if (item.eql(args[0]))
                    return lola.runtime.Value.initInteger(usize, index);
            }

            return .void;
        }

        fn Resize(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const list = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;

            const new_size = try args[0].toInteger(usize);
            const old_size = list.data.items.len;

            if (old_size > new_size) {
                for (list.data.items[new_size..]) |*item| {
                    item.deinit();
                }
                list.data.shrink(new_size);
            } else if (new_size > old_size) {
                try list.data.resize(new_size);
                for (list.data.items[old_size..]) |*item| {
                    item.* = .void;
                }
            }

            return .void;
        }

        fn Clear(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const list = context.get(Self);
            if (args.len != 0)
                return error.InvalidArgs;

            for (list.data.items) |*item| {
                item.deinit();
            }
            list.data.shrink(0);

            return .void;
        }
    };
};

pub const LoLaDictionary = struct {
    const Self = @This();

    const KV = struct {
        key: lola.runtime.Value,
        value: lola.runtime.Value,

        fn deinit(self: *KV) void {
            self.key.deinit();
            self.value.deinit();
            self.* = undefined;
        }
    };

    allocator: *std.mem.Allocator,
    data: std.ArrayList(KV),

    pub fn getMethod(self: *Self, name: []const u8) ?lola.runtime.Function {
        inline for (std.meta.declarations(funcs)) |decl| {
            if (std.mem.eql(u8, name, decl.name)) {
                return lola.runtime.Function{
                    .syncUser = .{
                        .context = lola.runtime.Context.init(Self, self),
                        .call = @field(funcs, decl.name),
                        .destructor = null,
                    },
                };
            }
        }
        return null;
    }

    pub fn destroyObject(self: *Self) void {
        for (self.data.items) |*item| {
            item.deinit();
        }
        self.data.deinit();
        self.allocator.destroy(self);
    }

    pub fn serializeObject(writer: lola.runtime.OutputStream.Writer, object: *Self) !void {
        try writer.writeIntLittle(u32, @intCast(u32, object.data.items.len));
        for (object.data.items) |item| {
            try item.key.serialize(writer);
            try item.value.serialize(writer);
        }
    }

    pub fn deserializeObject(allocator: *std.mem.Allocator, reader: lola.runtime.InputStream.Reader) !*Self {
        const item_count = try reader.readIntLittle(u32);
        var list = try allocator.create(Self);
        list.* = Self{
            .allocator = allocator,
            .data = std.ArrayList(KV).init(allocator),
        };
        errdefer list.destroyObject(); // this will also free memory!

        try list.data.resize(item_count);

        // sane init to make destroyObject not explode
        // (deinit a void value is a no-op)
        for (list.data.items) |*item| {
            item.* = KV{
                .key = .void,
                .value = .void,
            };
        }

        for (list.data.items) |*item| {
            item.key = try lola.runtime.Value.deserialize(reader, allocator);
            item.value = try lola.runtime.Value.deserialize(reader, allocator);
        }

        return list;
    }

    const funcs = struct {
        fn Set(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const dict = context.get(Self);
            if (args.len != 2)
                return error.InvalidArgs;

            if (args[1] == .void) {
                // short-circuit a argument `void` to a call to `Remove(key)`
                var result = try Remove(environment, context, args[0..1]);
                result.deinit();
                return .void;
            }

            var value = try args[1].clone();
            errdefer value.deinit();

            for (dict.data.items) |*item| {
                if (item.key.eql(args[0])) {
                    item.value.replaceWith(value);
                    return .void;
                }
            }

            var key = try args[0].clone();
            errdefer key.deinit();

            try dict.data.append(KV{
                .key = key,
                .value = value,
            });

            return .void;
        }

        fn Get(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const dict = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;

            for (dict.data.items) |item| {
                if (item.key.eql(args[0])) {
                    return try item.value.clone();
                }
            }

            return .void;
        }

        fn Contains(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const dict = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;

            for (dict.data.items) |item| {
                if (item.key.eql(args[0])) {
                    return lola.runtime.Value.initBoolean(true);
                }
            }

            return lola.runtime.Value.initBoolean(false);
        }

        fn Remove(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const dict = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;

            for (dict.data.items) |*item, index| {
                if (item.key.eql(args[0])) {

                    // use a fast swap-remove here
                    item.deinit();
                    const last_index = dict.data.items.len - 1;
                    dict.data.items[index] = dict.data.items[last_index];
                    dict.data.shrink(last_index);

                    return lola.runtime.Value.initBoolean(true);
                }
            }
            return lola.runtime.Value.initBoolean(false);
        }

        fn Clear(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const dict = context.get(Self);
            if (args.len != 0)
                return error.InvalidArgs;
            for (dict.data.items) |*item, index| {
                item.deinit();
            }
            dict.data.shrink(0);
            return .void;
        }

        fn GetCount(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const dict = context.get(Self);
            if (args.len != 0)
                return error.InvalidArgs;
            return lola.runtime.Value.initInteger(usize, dict.data.items.len);
        }

        fn GetKeys(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const dict = context.get(Self);
            if (args.len != 0)
                return error.InvalidArgs;
            var arr = try lola.runtime.Array.init(dict.allocator, dict.data.items.len);
            errdefer arr.deinit();

            for (dict.data.items) |item, index| {
                arr.contents[index].replaceWith(try item.key.clone());
            }

            return lola.runtime.Value.fromArray(arr);
        }

        fn GetValues(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
            const dict = context.get(Self);
            if (args.len != 0)
                return error.InvalidArgs;
            var arr = try lola.runtime.Array.init(dict.allocator, dict.data.items.len);
            errdefer arr.deinit();

            for (dict.data.items) |item, index| {
                arr.contents[index].replaceWith(try item.value.clone());
            }

            return lola.runtime.Value.fromArray(arr);
        }
    };
};
