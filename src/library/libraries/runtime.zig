// This file implements the LoLa Runtime Library.

const std = @import("std");
const builtin = @import("builtin");
const lola = @import("../main.zig");
const root = @import("root");

const GlobalObjectPool = if (builtin.is_test)
    // we need to do a workaround here for testing purposes
    lola.runtime.objects.ObjectPool([_]type{
        LoLaList,
        LoLaDictionary,
    })
else if (@hasDecl(root, "ObjectPool"))
    root.ObjectPool
else
    @compileError("Please define and use a global ObjectPool type to use the runtime classes.");

comptime {
    if (builtin.is_test) {
        const T = lola.runtime.objects.ObjectPool([_]type{
            LoLaList,
            LoLaDictionary,
        });

        if (!T.serializable)
            @compileError("Both LoLaList and LoLaDictionary must be serializable!");
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

    try env.installModule(@This(), lola.runtime.Context.null_pointer);
}

// fn Sleep(call_context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.AsyncFunctionCall {
//     const allocator = call_context.get(std.mem.Allocator);

//     if (args.len != 1)
//         return error.InvalidArgs;
//     const seconds = try args[0].toNumber();

//     const Context = struct {
//         allocator: std.mem.Allocator,
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
//             fn execute(exec_context: lola.runtime.Context) anyerror!?lola.runtime.value.Value {
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

pub fn Print(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
    _ = environment;
    _ = context;

    var stdout_writer = std.fs.File.stdout().writer(&.{});
    const stdout = &stdout_writer.interface;
    for (args) |value| {
        switch (value) {
            .string => |str| try stdout.writeAll(str.contents),
            else => try stdout.print("{f}", .{value}),
        }
    }
    try stdout.writeAll("\n");
    return .void;
}

pub fn Exit(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
    _ = environment;
    _ = context;

    if (args.len != 1)
        return error.InvalidArgs;

    const status = try args[0].toInteger(u8);
    std.process.exit(status);
}

pub fn ReadFile(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
    _ = context;

    if (args.len != 1)
        return error.InvalidArgs;

    const path = try args[0].toString();

    var file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch return .void;
    defer file.close();

    // 2 GB
    const contents = try file.readToEndAlloc(environment.allocator, 2 << 30);

    return lola.runtime.value.Value.fromString(lola.runtime.value.String.initFromOwned(environment.allocator, contents));
}

pub fn FileExists(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
    _ = environment;
    _ = context;

    if (args.len != 1)
        return error.InvalidArgs;

    const path = try args[0].toString();

    var file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch return lola.runtime.value.Value.initBoolean(false);
    file.close();

    return lola.runtime.value.Value.initBoolean(true);
}

pub fn WriteFile(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
    _ = environment;
    _ = context;

    if (args.len != 2)
        return error.InvalidArgs;

    const path = try args[0].toString();
    const value = try args[1].toString();

    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    try file.writeAll(value);

    return .void;
}

pub fn CreateList(environment: *lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
    _ = context;
    if (args.len > 1)
        return error.InvalidArgs;

    if (args.len > 0) _ = try args[0].toArray();

    const list = try environment.allocator.create(LoLaList);
    errdefer environment.allocator.destroy(list);

    list.* = LoLaList{
        .allocator = environment.allocator,
        .data = std.ArrayList(lola.runtime.value.Value).empty,
    };

    if (args.len > 0) {
        const array = args[0].toArray() catch unreachable;

        errdefer list.data.deinit(environment.allocator);
        try list.data.resize(environment.allocator, array.contents.len);

        for (list.data.items) |*item| {
            item.* = .void;
        }

        errdefer for (list.data.items) |*item| {
            item.deinit();
        };
        for (list.data.items, 0..) |*item, index| {
            item.* = try array.contents[index].clone();
        }
    }

    return lola.runtime.value.Value.initObject(
        try environment.objectPool.castTo(GlobalObjectPool).createObject(list),
    );
}

pub fn CreateDictionary(environment: *lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
    _ = context;
    if (args.len != 0)
        return error.InvalidArgs;

    const list = try environment.allocator.create(LoLaDictionary);
    errdefer environment.allocator.destroy(list);

    list.* = LoLaDictionary{
        .allocator = environment.allocator,
        .data = std.ArrayList(LoLaDictionary.KV).empty,
    };

    return lola.runtime.value.Value.initObject(
        try environment.objectPool.castTo(GlobalObjectPool).createObject(list),
    );
}

pub const LoLaList = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: std.ArrayList(lola.runtime.value.Value),

    pub fn getMethod(self: *Self, name: []const u8) ?lola.runtime.Function {
        inline for (comptime std.meta.declarations(funcs)) |decl| {
            if (std.mem.eql(u8, name, decl.name)) {
                return lola.runtime.Function{
                    .syncUser = .{
                        .context = lola.runtime.Context.make(*Self, self),
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
        self.data.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn serializeObject(writer: lola.runtime.objects.OutputStream.Writer, object: *Self) !void {
        try writer.writeInt(u32, @as(u32, @intCast(object.data.items.len)), .little);
        for (object.data.items) |item| {
            try item.serialize(writer);
        }
    }

    pub fn deserializeObject(allocator: std.mem.Allocator, reader: lola.runtime.objects.InputStream.Reader) !*Self {
        const item_count = try reader.takeInt(u32, .little);
        var list = try allocator.create(Self);
        list.* = Self{
            .allocator = allocator,
            .data = std.ArrayList(lola.runtime.value.Value).empty,
        };
        errdefer list.destroyObject(); // this will also free memory!

        try list.data.resize(allocator, item_count);

        // sane init to make destroyObject not explode
        // (deinit a void value is a no-op)
        for (list.data.items) |*item| {
            item.* = .void;
        }

        for (list.data.items) |*item| {
            item.* = try lola.runtime.value.Value.deserialize(reader, allocator);
        }

        return list;
    }

    const funcs = struct {
        pub fn Add(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const list: *Self = context.cast(*Self);
            if (args.len != 1)
                return error.InvalidArgs;

            var cloned = try args[0].clone();
            errdefer cloned.deinit();

            try list.data.append(list.allocator, cloned);

            return .void;
        }

        pub fn Remove(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const list: *Self = context.cast(*Self);
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
            list.data.shrinkRetainingCapacity(dst_index);

            return .void;
        }

        pub fn RemoveAt(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const list: *Self = context.cast(*Self);
            if (args.len != 1)
                return error.InvalidArgs;

            const index = try args[0].toInteger(usize);

            if (index < list.data.items.len) {
                list.data.items[index].deinit();
                std.mem.copyForwards(
                    lola.runtime.value.Value,
                    list.data.items[index..],
                    list.data.items[index + 1 ..],
                );
                list.data.shrinkRetainingCapacity(list.data.items.len - 1);
            }

            return .void;
        }

        pub fn GetCount(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const list: *Self = context.cast(*Self);
            if (args.len != 0)
                return error.InvalidArgs;
            return lola.runtime.value.Value.initInteger(usize, list.data.items.len);
        }

        pub fn GetItem(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const list: *Self = context.cast(*Self);
            if (args.len != 1)
                return error.InvalidArgs;
            const index = try args[0].toInteger(usize);
            if (index >= list.data.items.len)
                return error.OutOfRange;

            return try list.data.items[index].clone();
        }

        pub fn SetItem(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const list: *Self = context.cast(*Self);
            if (args.len != 2)
                return error.InvalidArgs;
            const index = try args[0].toInteger(usize);
            if (index >= list.data.items.len)
                return error.OutOfRange;

            const cloned = try args[1].clone();

            list.data.items[index].replaceWith(cloned);

            return .void;
        }

        pub fn ToArray(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const list: *Self = context.cast(*Self);
            if (args.len != 0)
                return error.InvalidArgs;

            var array = try lola.runtime.value.Array.init(list.allocator, list.data.items.len);
            errdefer array.deinit();

            for (array.contents, 0..) |*item, index| {
                item.* = try list.data.items[index].clone();
            }

            return lola.runtime.value.Value.fromArray(array);
        }

        pub fn IndexOf(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const list: *Self = context.cast(*Self);
            if (args.len != 1)
                return error.InvalidArgs;

            for (list.data.items, 0..) |item, index| {
                if (item.eql(args[0]))
                    return lola.runtime.value.Value.initInteger(usize, index);
            }

            return .void;
        }

        pub fn Resize(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const list: *Self = context.cast(*Self);
            if (args.len != 1)
                return error.InvalidArgs;

            const new_size = try args[0].toInteger(usize);
            const old_size = list.data.items.len;

            if (old_size > new_size) {
                for (list.data.items[new_size..]) |*item| {
                    item.deinit();
                }
                list.data.shrinkAndFree(list.allocator, new_size);
            } else if (new_size > old_size) {
                try list.data.resize(list.allocator, new_size);
                for (list.data.items[old_size..]) |*item| {
                    item.* = .void;
                }
            }

            return .void;
        }

        pub fn Clear(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const list: *Self = context.cast(*Self);
            if (args.len != 0)
                return error.InvalidArgs;

            for (list.data.items) |*item| {
                item.deinit();
            }
            list.data.shrinkAndFree(list.allocator, 0);

            return .void;
        }
    };
};

pub const LoLaDictionary = struct {
    const Self = @This();

    const KV = struct {
        key: lola.runtime.value.Value,
        value: lola.runtime.value.Value,

        fn deinit(self: *KV) void {
            self.key.deinit();
            self.value.deinit();
            self.* = undefined;
        }
    };

    allocator: std.mem.Allocator,
    data: std.ArrayList(KV),

    pub fn getMethod(self: *Self, name: []const u8) ?lola.runtime.Function {
        inline for (comptime std.meta.declarations(funcs)) |decl| {
            if (std.mem.eql(u8, name, decl.name)) {
                return lola.runtime.Function{
                    .syncUser = .{
                        .context = lola.runtime.Context.make(*Self, self),
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
        self.data.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn serializeObject(writer: lola.runtime.objects.OutputStream.Writer, object: *Self) !void {
        try writer.writeInt(u32, @as(u32, @intCast(object.data.items.len)), .little);
        for (object.data.items) |item| {
            try item.key.serialize(writer);
            try item.value.serialize(writer);
        }
    }

    pub fn deserializeObject(allocator: std.mem.Allocator, reader: lola.runtime.objects.InputStream.Reader) !*Self {
        const item_count = try reader.takeInt(u32, .little);
        var list = try allocator.create(Self);
        list.* = Self{
            .allocator = allocator,
            .data = std.ArrayList(KV).empty,
        };
        errdefer list.destroyObject(); // this will also free memory!

        try list.data.resize(allocator, item_count);

        // sane init to make destroyObject not explode
        // (deinit a void value is a no-op)
        for (list.data.items) |*item| {
            item.* = KV{
                .key = .void,
                .value = .void,
            };
        }

        for (list.data.items) |*item| {
            item.key = try lola.runtime.value.Value.deserialize(reader, allocator);
            item.value = try lola.runtime.value.Value.deserialize(reader, allocator);
        }

        return list;
    }

    const funcs = struct {
        pub fn Set(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            const dict: *Self = context.cast(*Self);
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

            try dict.data.append(dict.allocator, KV{
                .key = key,
                .value = value,
            });

            return .void;
        }

        pub fn Get(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const dict: *Self = context.cast(*Self);
            if (args.len != 1)
                return error.InvalidArgs;

            for (dict.data.items) |item| {
                if (item.key.eql(args[0])) {
                    return try item.value.clone();
                }
            }

            return .void;
        }

        pub fn Contains(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const dict: *Self = context.cast(*Self);
            if (args.len != 1)
                return error.InvalidArgs;

            for (dict.data.items) |item| {
                if (item.key.eql(args[0])) {
                    return lola.runtime.value.Value.initBoolean(true);
                }
            }

            return lola.runtime.value.Value.initBoolean(false);
        }

        pub fn Remove(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const dict: *Self = context.cast(*Self);
            if (args.len != 1)
                return error.InvalidArgs;

            for (dict.data.items, 0..) |*item, index| {
                if (item.key.eql(args[0])) {

                    // use a fast swap-remove here
                    item.deinit();
                    const last_index = dict.data.items.len - 1;
                    dict.data.items[index] = dict.data.items[last_index];
                    dict.data.shrinkRetainingCapacity(last_index);

                    return lola.runtime.value.Value.initBoolean(true);
                }
            }
            return lola.runtime.value.Value.initBoolean(false);
        }

        pub fn Clear(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const dict: *Self = context.cast(*Self);
            if (args.len != 0)
                return error.InvalidArgs;
            for (dict.data.items) |*item| {
                item.deinit();
            }
            dict.data.shrinkAndFree(dict.allocator, 0);
            return .void;
        }

        pub fn GetCount(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const dict: *Self = context.cast(*Self);
            if (args.len != 0)
                return error.InvalidArgs;
            return lola.runtime.value.Value.initInteger(usize, dict.data.items.len);
        }

        pub fn GetKeys(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const dict: *Self = context.cast(*Self);
            if (args.len != 0)
                return error.InvalidArgs;
            var arr = try lola.runtime.value.Array.init(dict.allocator, dict.data.items.len);
            errdefer arr.deinit();

            for (dict.data.items, 0..) |item, index| {
                arr.contents[index].replaceWith(try item.key.clone());
            }

            return lola.runtime.value.Value.fromArray(arr);
        }

        pub fn GetValues(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.value.Value) anyerror!lola.runtime.value.Value {
            _ = environment;
            const dict: *Self = context.cast(*Self);
            if (args.len != 0)
                return error.InvalidArgs;
            var arr = try lola.runtime.value.Array.init(dict.allocator, dict.data.items.len);
            errdefer arr.deinit();

            for (dict.data.items, 0..) |item, index| {
                arr.contents[index].replaceWith(try item.value.clone());
            }

            return lola.runtime.value.Value.fromArray(arr);
        }
    };
};
