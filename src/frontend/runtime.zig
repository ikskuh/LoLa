// This file implements the LoLa Runtime Library.

const std = @import("std");
const lola = @import("lola");

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
    var env = try lola.Environment.init(std.testing.allocator, &empty_compile_unit);
    defer env.deinit();

    // TODO: Reinsert this
    try install(&env, std.testing.allocator);
}

const async_functions = struct {
    // fn Sleep(call_context: lola.Context, args: []const lola.Value) anyerror!lola.AsyncFunctionCall {
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

    //     return lola.AsyncFunctionCall{
    //         .context = lola.Context.init(Context, ptr),
    //         .destructor = struct {
    //             fn dtor(exec_context: lola.Context) void {
    //                 const ctx = exec_context.get(Context);
    //                 ctx.allocator.destroy(ctx);
    //             }
    //         }.dtor,
    //         .execute = struct {
    //             fn execute(exec_context: lola.Context) anyerror!?lola.Value {
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
    fn Print(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
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

    fn Exit(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
        if (args.len != 1)
            return error.InvalidArgs;

        const status = try args[0].toInteger(u8);
        std.process.exit(status);
    }

    fn ReadFile(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;

        const path = try args[0].toString();

        var file = std.fs.cwd().openFile(path, .{ .read = true, .write = false }) catch return .void;
        defer file.close();

        // 2 GB
        var contents = try file.reader().readAllAlloc(allocator, 2 << 30);

        return lola.Value.fromString(lola.String.initFromOwned(allocator, contents));
    }

    fn FileExists(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len != 1)
            return error.InvalidArgs;

        const path = try args[0].toString();

        var file = std.fs.cwd().openFile(path, .{ .read = true, .write = false }) catch return lola.Value.initBoolean(false);
        file.close();

        return lola.Value.initBoolean(true);
    }

    fn WriteFile(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
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

    fn CreateList(environment: *lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
        const allocator = context.get(std.mem.Allocator);
        if (args.len > 1)
            return error.InvalidArgs;

        if (args.len > 0) _ = try args[0].toArray();

        const list = try allocator.create(LoLaList);
        errdefer allocator.destroy(list);

        list.* = LoLaList{
            .allocator = allocator,
            .data = std.ArrayList(lola.Value).init(allocator),
        };

        if (args.len > 0) {
            const array = args[0].toArray() catch unreachable;
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

        return lola.Value.initObject(
            try environment.objectPool.createObject(lola.Object.init(list)),
        );
    }
};

const LoLaList = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    data: std.ArrayList(lola.Value),

    pub fn getMethod(self: *Self, name: []const u8) ?lola.Function {
        inline for (std.meta.declarations(funcs)) |decl| {
            if (std.mem.eql(u8, name, decl.name)) {
                return lola.Function{
                    .syncUser = .{
                        .context = lola.Context.init(Self, self),
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

    const funcs = struct {
        fn Add(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
            const list = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;

            var cloned = try args[0].clone();
            errdefer cloned.deinit();

            try list.data.append(cloned);

            return .void;
        }

        fn Remove(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
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

        fn RemoveAt(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
            const list = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;

            const index = try args[0].toInteger(usize);

            if (index < list.data.items.len) {
                list.data.items[index].deinit();
                std.mem.copy(
                    lola.Value,
                    list.data.items[index..],
                    list.data.items[index + 1 ..],
                );
                list.data.shrink(list.data.items.len - 1);
            }

            return .void;
        }

        fn GetCount(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
            const list = context.get(Self);
            if (args.len != 0)
                return error.InvalidArgs;
            return lola.Value.initInteger(usize, list.data.items.len);
        }

        fn GetItem(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
            const list = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;
            const index = try args[0].toInteger(usize);
            if (index >= list.data.items.len)
                return error.OutOfRange;

            return try list.data.items[index].clone();
        }

        fn SetItem(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
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

        fn ToArray(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
            const list = context.get(Self);
            if (args.len != 0)
                return error.InvalidArgs;

            var array = try lola.Array.init(list.allocator, list.data.items.len);
            errdefer array.deinit();

            for (array.contents) |*item, index| {
                item.* = try list.data.items[index].clone();
            }

            return lola.Value.fromArray(array);
        }

        fn IndexOf(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
            const list = context.get(Self);
            if (args.len != 1)
                return error.InvalidArgs;

            for (list.data.items) |item, index| {
                if (item.eql(args[0]))
                    return lola.Value.initInteger(usize, index);
            }

            return .void;
        }

        fn Resize(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
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

        fn Clear(environment: *const lola.Environment, context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
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
