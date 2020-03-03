const std = @import("std");
const lola = @import("lola");

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var cu = blk: {
        var file = try std.fs.cwd().openFile("develop.lm", .{ .read = true, .write = false });
        defer file.close();

        var stream = file.inStream();
        break :blk try lola.CompileUnit.loadFromStream(allocator, std.fs.File.InStream.Error, &stream.stream);
    };
    defer cu.deinit();

    var stream = &std.io.getStdOut().outStream().stream;

    try stream.write("metadata:\n");
    try stream.print("\tcomment:         {}\n", .{cu.comment});
    try stream.print("\tcode size:       {} bytes\n", .{cu.code.len});
    try stream.print("\tnum globals:     {}\n", .{cu.globalCount});
    try stream.print("\tnum temporaries: {}\n", .{cu.temporaryCount});
    try stream.print("\tnum functions:   {}\n", .{cu.functions.len});
    try stream.print("\tnum debug syms:  {}\n", .{cu.debugSymbols.len});

    try stream.write("disassembly:\n");

    try lola.disassemble(std.fs.File.OutStream.Error, stream, cu, lola.DisassemblerOptions{
        .addressPrefix = true,
    });

    var counterAllocator = std.testing.LeakCountAllocator.init(std.heap.direct_allocator);
    defer {
        if (counterAllocator.count > 0) {
            std.debug.warn("error - detected leaked allocations without matching free: {}\n", .{counterAllocator.count});
        }
    }

    // const OI = lola.ObjectInterface{
    //     .context = undefined,
    //     .isHandleValid = struct {
    //         fn f(ctx: []const u8, h: lola.ObjectHandle) bool {
    //             return (h == 1) or (h == 2);
    //         }
    //     }.f,
    //     .getFunction = struct {
    //         fn f(context: []const u8, object: lola.ObjectHandle, name: []const u8) error{ObjectNotFound}!?lola.Function {
    //             if (object != 1 and object != 2)
    //                 return error.ObjectNotFound;
    //             return lola.Function{
    //                 .syncUser = lola.UserFunction{
    //                     .context = if (object == 1) "Obj1" else "Obj2",
    //                     .destructor = null,
    //                     .call = struct {
    //                         fn call(obj_context: []const u8, args: []const lola.Value) anyerror!lola.Value {
    //                             return lola.Value.initString(std.testing.allocator, obj_context);
    //                         }
    //                     }.call,
    //                 },
    //             };
    //         }
    //     }.f,
    // };

    var env = try lola.Environment.init(std.heap.direct_allocator, &cu);
    defer env.deinit();

    try env.functions.putNoClobber("Print", lola.Function{
        .syncUser = lola.UserFunction{
            .context = undefined,
            .destructor = null,
            .call = struct {
                fn call(context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
                    var stdout = &std.io.getStdOut().outStream().stream;
                    for (args) |value, i| {
                        if (i > 0)
                            try stdout.write(" ");
                        try stdout.print("{}", .{value});
                    }
                    try stdout.write("\n");
                    return lola.Value.initVoid();
                }
            }.call,
        },
    });

    try env.functions.putNoClobber("Length", lola.Function{
        .syncUser = lola.UserFunction{
            .context = undefined,
            .destructor = null,
            .call = struct {
                fn call(context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
                    if (args.len != 1)
                        return error.InvalidArgs;
                    return switch (args[0]) {
                        .string => |str| lola.Value.initNumber(@intToFloat(f64, str.contents.len)),
                        .array => |arr| lola.Value.initNumber(@intToFloat(f64, arr.contents.len)),
                        else => error.TypeMismatch,
                    };
                }
            }.call,
        },
    });

    try env.functions.putNoClobber("Sleep", lola.Function{
        .asyncUser = lola.AsyncUserFunction{
            .context = undefined,
            .destructor = null,
            .call = struct {
                fn call(call_context: lola.Context, args: []const lola.Value) anyerror!lola.AsyncFunctionCall {
                    const ptr = try std.heap.direct_allocator.create(f64);

                    if (args.len > 0) {
                        ptr.* = try args[0].toNumber();
                    } else {
                        ptr.* = 1;
                    }

                    return lola.AsyncFunctionCall{
                        .context = lola.Context.init(f64, ptr),
                        .destructor = struct {
                            fn dtor(exec_context: lola.Context) void {
                                std.heap.direct_allocator.destroy(exec_context.get(f64));
                            }
                        }.dtor,
                        .execute = struct {
                            fn execute(exec_context: lola.Context) anyerror!?lola.Value {
                                const count = exec_context.get(f64);

                                count.* -= 1;

                                if (count.* <= 0) {
                                    return lola.Value.initVoid();
                                } else {
                                    return null;
                                }
                            }
                        }.execute,
                    };
                }
            }.call,
        },
    });

    var refValue = lola.Value.initNumber(23.0);

    const MyObject = struct {
        const Self = @This();

        name: []const u8,

        fn getMethod(self: *Self, name: []const u8) ?lola.Function {
            std.debug.warn("getMethod({}, {})\n", .{
                self.name,
                name,
            });
            if (std.mem.eql(u8, name, "call")) {
                std.debug.warn("return call!\n", .{});
                return lola.Function{
                    .syncUser = lola.UserFunction{
                        .context = lola.Context.init(Self, self),
                        .destructor = null,
                        .call = struct {
                            fn call(obj_context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
                                return lola.Value.initString(std.testing.allocator, obj_context.get(Self).name);
                            }
                        }.call,
                    },
                };
            }
            return null;
        }

        fn destroyObject(self: Self) void {
            std.debug.warn("destroyObject({})\n", .{
                self.name,
            });
        }
    };

    const LoLaStack = struct {
        const Self = @This();

        allocator: *std.mem.Allocator,
        contents: std.ArrayList(lola.Value),

        fn deinit(self: Self) void {
            for (self.contents.toSliceConst()) |item| {
                item.deinit();
            }
            self.contents.deinit();
        }

        fn getMethod(self: *Self, name: []const u8) ?lola.Function {
            if (std.mem.eql(u8, name, "Push")) {
                return lola.Function{
                    .syncUser = lola.UserFunction{
                        .context = lola.Context.init(Self, self),
                        .destructor = null,
                        .call = struct {
                            fn call(obj_context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
                                for (args) |arg| {
                                    const v = try arg.clone();
                                    errdefer v.deinit();

                                    try obj_context.get(Self).contents.append(v);
                                }
                                return lola.Value.initVoid();
                            }
                        }.call,
                    },
                };
            } else if (std.mem.eql(u8, name, "Pop")) {
                return lola.Function{
                    .syncUser = lola.UserFunction{
                        .context = lola.Context.init(Self, self),
                        .destructor = null,
                        .call = struct {
                            fn call(obj_context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
                                var stack = obj_context.get(Self);
                                if (stack.contents.len > 0) {
                                    return stack.contents.pop();
                                } else {
                                    return lola.Value.initVoid();
                                }
                            }
                        }.call,
                    },
                };
            } else if (std.mem.eql(u8, name, "GetSize")) {
                return lola.Function{
                    .syncUser = lola.UserFunction{
                        .context = lola.Context.init(Self, self),
                        .destructor = null,
                        .call = struct {
                            fn call(obj_context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
                                return lola.Value.initNumber(@intToFloat(f64, obj_context.get(Self).contents.len));
                            }
                        }.call,
                    },
                };
            }
            return null;
        }

        fn destroyObject(self: Self) void {
            self.deinit();
            self.allocator.destroy(&self);
            std.debug.warn("destroy stack\n", .{});
        }
    };

    try env.functions.putNoClobber("CreateStack", lola.Function{
        .syncUser = lola.UserFunction{
            .context = lola.Context.init(lola.Environment, &env),
            .destructor = null,
            .call = struct {
                fn call(context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
                    var stack = try std.testing.allocator.create(LoLaStack);
                    errdefer std.testing.allocator.destroy(stack);

                    stack.* = LoLaStack{
                        .allocator = std.testing.allocator,
                        .contents = std.ArrayList(lola.Value).init(std.testing.allocator),
                    };
                    errdefer stack.deinit();

                    const oid = try context.get(lola.Environment).objectPool.createObject(try lola.Object.init(.{stack}));

                    return lola.Value.initObject(oid);
                }
            }.call,
        },
    });

    var obj1 = MyObject{
        .name = "Object 1",
    };
    var obj2 = MyObject{
        .name = "Object 2",
    };

    const objref1 = try env.objectPool.createObject(try lola.Object.init(.{&obj1}));
    const objref2 = try env.objectPool.createObject(try lola.Object.init(.{&obj2}));

    try env.objectPool.retainObject(objref1);
    try env.objectPool.retainObject(objref2);

    try env.namedGlobals.putNoClobber("valGlobal", lola.NamedGlobal.initStored(lola.Value.initNumber(42.0)));
    try env.namedGlobals.putNoClobber("refGlobal", lola.NamedGlobal.initReferenced(&refValue));
    try env.namedGlobals.putNoClobber("objGlobal1", lola.NamedGlobal.initStored(lola.Value.initObject(objref1)));
    try env.namedGlobals.putNoClobber("objGlobal2", lola.NamedGlobal.initStored(lola.Value.initObject(objref2)));

    // var smartCounter: u32 = 0;
    // try env.namedGlobals.putNoClobber("smartCounter", lola.NamedGlobal.initSmart(lola.SmartGlobal.initRead(
    //     lola.SmartGlobal.Context.init(u32, &smartCounter),
    //     struct {
    //         fn read(ctx: lola.SmartGlobal.Context) lola.Value {
    //             const ptr = ctx.get(u32);
    //             const res = ptr.*;
    //             ptr.* += 1;
    //             return lola.Value.initNumber(@intToFloat(f64, res));
    //         }
    //     }.read,
    // )));

    // try env.namedGlobals.putNoClobber("smartDumper", lola.NamedGlobal.initSmart(lola.SmartGlobal.initRead(
    //     lola.SmartGlobal.Context.init(u32, &smartCounter),
    //     struct {
    //         fn read(ctx: lola.SmartGlobal.Context) lola.Value {
    //             const ptr = ctx.get(u32);
    //             const res = ptr.*;
    //             ptr.* += 1;
    //             return lola.Value.initNumber(@intToFloat(f64, res));
    //         }
    //     }.read,
    // )));

    var vm = try lola.VM.init(&counterAllocator.allocator, &env);
    defer vm.deinit();

    defer {
        std.debug.warn("Stack:\n", .{});
        for (vm.stack.toSliceConst()) |item, i| {
            std.debug.warn("[{}]\t= {}\n", .{ i, item });
        }
    }

    while (true) {
        var result = vm.execute(1000) catch |err| {
            std.debug.warn("Failed to execute code: {}\n", .{err});
            return err;
        };

        const previous = env.objectPool.objects.size;

        env.objectPool.clearUsageCounters();

        try env.objectPool.walkEnvironment(env);
        try env.objectPool.walkVM(vm);

        env.objectPool.collectGarbage();

        const now = env.objectPool.objects.size;

        std.debug.warn("result: {}\tcollected {} objects\n", .{ result, previous - now });
        if (result == .completed)
            break;
    }

    for (env.scriptGlobals) |global, i| {
        std.debug.warn("[{}]\t= {}\n", .{ i, global });
    }

    // std.debug.assert(refValue.eql(lola.Value.initVoid()));
}
