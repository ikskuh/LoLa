const std = @import("std");
const lola = @import("lola");
const argsParser = @import("args");

// lola compile foo.lola -o foo.lm
pub fn main() !u8 {
    var args = std.process.args();

    var argsAllocator = std.heap.c_allocator;

    const exeName = try (args.next(argsAllocator) orelse {
        try std.io.getStdErr().writer().writeAll("Failed to get executable name from the argument list!\n");
        return 1;
    });
    defer argsAllocator.free(exeName);

    const module = try (args.next(argsAllocator) orelse {
        try print_usage();
        return 1;
    });
    defer argsAllocator.free(module);

    if (std.mem.eql(u8, module, "compile")) {
        const options = try argsParser.parse(CompileCLI, &args, argsAllocator);
        defer options.deinit();

        return try compile(options.options, options.positionals);
    } else if (std.mem.eql(u8, module, "dump")) {
        const options = try argsParser.parse(DisassemblerCLI, &args, argsAllocator);
        defer options.deinit();

        return try disassemble(options.options, options.positionals);
    } else if (std.mem.eql(u8, module, "run")) {
        const options = try argsParser.parse(RunCLI, &args, argsAllocator);
        defer options.deinit();

        return try run(options.options, options.positionals);
    } else if (std.mem.eql(u8, module, "help")) {
        try print_usage();
        return 0;
    } else {
        try std.io.getStdErr().writer().print(
            "Unrecognized command: {}\nSee `lola help` for detailed usage information.\n",
            .{
                module,
            },
        );
        return 1;
    }

    return 0;
}

pub fn print_usage() !void {
    const usage_msg =
        \\Usage: lola [command] [options]
        \\
        \\Commands:
        \\  compile [source]                   Compiles the given source file into a module.
        \\  dump [module]                      Disassembles the given module.
        \\  run [file]                         Runs the given file. Both modules and source files are allowed.
        \\
        \\General Options:
        \\  -o [output file]                   Defines the output file for the action.
        \\
        \\Disassemble Options:
        \\  --with-offset, -O                  Adds offsets to the disassembly.
        \\  --with-hexdump, -b                 Adds the hex dump in the disassembly.
        \\
        \\Run Options:
        \\  --limit [n]                        Limits execution to [n] instructions, then halts.
        \\  --mode [autodetect|source|module]  Determines if run should interpret the file as a source file,
        \\                                     a precompiled module or if it should autodetect the file type.
        \\  --no-stdlib                        Removes the standard library from the environment.
        \\  --no-runtime                       Removes the system runtime from the environment.
        \\
    ;
    // \\  -S                      Intermixes the disassembly with the original source code if possible.
    try std.io.getStdErr().writer().writeAll(usage_msg);
}

const DisassemblerCLI = struct {
    @"output": ?[]const u8 = null,
    @"metadata": bool = false,
    @"with-offset": bool = false,
    @"with-hexdump": bool = false,
    // @"intermix-source": bool = false,

    pub const shorthands = .{
        // .S = "intermix-source",
        .b = "with-hexdump",
        .O = "with-offset",
        .o = "output",
        .m = "metadata",
    };
};

fn disassemble(options: DisassemblerCLI, files: []const []const u8) !u8 {
    var stream = std.io.getStdOut().writer();

    if (files.len == 0) {
        try print_usage();
        return 1;
    }

    var logfile: ?std.fs.File = null;
    defer if (logfile) |f|
        f.close();

    if (options.output) |outfile| {
        logfile = try std.fs.cwd().createFile(outfile, .{
            .read = false,
            .truncate = true,
            .exclusive = false,
        });
        stream = logfile.?.writer();
    }

    for (files) |arg| {
        if (files.len != 1) {
            try stream.print("Disassembly for {}:\n", .{arg});
        }

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        const allocator = &arena.allocator;

        var cu = blk: {
            var file = try std.fs.cwd().openFile(arg, .{ .read = true, .write = false });
            defer file.close();

            break :blk try lola.CompileUnit.loadFromStream(allocator, file.reader());
        };
        defer cu.deinit();

        if (options.metadata) {
            try stream.writeAll("metadata:\n");
            try stream.print("\tcomment:         {}\n", .{cu.comment});
            try stream.print("\tcode size:       {} bytes\n", .{cu.code.len});
            try stream.print("\tnum globals:     {}\n", .{cu.globalCount});
            try stream.print("\tnum temporaries: {}\n", .{cu.temporaryCount});
            try stream.print("\tnum functions:   {}\n", .{cu.functions.len});
            try stream.print("\tnum debug syms:  {}\n", .{cu.debugSymbols.len});

            try stream.writeAll("disassembly:\n");
        }

        try lola.disassemble(stream, cu, lola.DisassemblerOptions{
            .addressPrefix = options.@"with-offset",
            .hexwidth = if (options.@"with-hexdump") 8 else null,
            .labelOutput = true,
            .instructionOutput = true,
        });
    }

    return 0;
}

const CompileCLI = struct {
    @"output": ?[]const u8 = null,

    pub const shorthands = .{
        .o = "output",
    };
};

const ModuleBuffer = extern struct {
    data: [*]u8,
    length: usize,
};

extern fn compile_lola_source(source: [*]const u8, sourceLength: usize, module: *ModuleBuffer) bool;

fn compile(options: CompileCLI, files: []const []const u8) !u8 {
    if (files.len != 1) {
        try print_usage();
        return 1;
    }

    const allocator = std.heap.c_allocator;

    const inname = files[0];

    const outname = if (options.output) |name|
        name
    else blk: {
        var name = try allocator.alloc(u8, inname.len + 3);
        std.mem.copy(u8, name[0..inname.len], inname);
        std.mem.copy(u8, name[inname.len..], ".lm");
        break :blk name;
    };
    defer if (options.output == null)
        allocator.free(outname);

    const cu = try compileFileToUnit(allocator, inname);
    defer cu.deinit();

    {
        var file = try std.fs.cwd().createFile(outname, .{ .truncate = true, .read = false, .exclusive = false });
        defer file.close();

        try cu.saveToStream(file.writer());
    }

    return 0;
}

const RunCLI = struct {
    @"limit": ?u32 = null,
    @"mode": enum { autodetect, source, module } = .autodetect,
    @"no-stdlib": bool = false,
    @"no-runtime": bool = false,
};

fn run(options: RunCLI, files: []const []const u8) !u8 {
    if (files.len != 1) {
        try print_usage();
        return 1;
    }

    const allocator = std.heap.c_allocator;

    var cu = switch (options.mode) {
        .autodetect => loadModuleFromFile(allocator, files[0]) catch |err| if (err == error.InvalidFormat)
            try compileFileToUnit(allocator, files[0])
        else
            return err,
        .module => try loadModuleFromFile(allocator, files[0]),
        .source => try compileFileToUnit(allocator, files[0]),
    };
    defer cu.deinit();

    var env = try lola.Environment.init(allocator, &cu);
    defer env.deinit();

    if (!options.@"no-stdlib") {
        try lola.std.install(&env, allocator);
    }

    if (!options.@"no-runtime") {
        try env.installFunction("Print", lola.Function.initSimpleUser(struct {
            fn call(context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
                var stdout = std.io.getStdOut().writer();
                for (args) |value, i| {
                    switch (value) {
                        .string => |str| try stdout.writeAll(str.contents),
                        else => try stdout.print("{}", .{value}),
                    }
                }
                try stdout.writeAll("\n");
                return lola.Value.initVoid();
            }
        }.call));

        try env.installFunction("Expect", lola.Function.initSimpleUser(struct {
            fn call(context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
                if (args.len != 1)
                    return error.InvalidArgs;
                const assertion = try args[0].toBoolean();

                if (!assertion)
                    return error.AssertionFailed;

                return lola.Value.initVoid();
            }
        }.call));

        try env.installFunction("ExpectEqual", lola.Function.initSimpleUser(struct {
            fn call(context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
                if (args.len != 2)
                    return error.InvalidArgs;
                if (!args[0].eql(args[1])) {
                    std.log.err("Expected {}, got {}\n", .{ args[1], args[0] });
                    return error.AssertionFailed;
                }

                return lola.Value.initVoid();
            }
        }.call));

        try env.installFunction("Exit", lola.Function.initSimpleUser(struct {
            fn call(context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
                if (args.len != 1)
                    return error.InvalidArgs;

                const status = try args[0].toInteger(u8);
                std.process.exit(status);
            }
        }.call));
    }

    var vm = try lola.VM.init(allocator, &env);
    defer vm.deinit();

    while (true) {
        var result = vm.execute(options.limit) catch |err| {
            try std.io.getStdErr().writer().print("Panic during execution: {}\n", .{@errorName(err)});
            return err;
        };

        env.objectPool.clearUsageCounters();

        try env.objectPool.walkEnvironment(env);
        try env.objectPool.walkVM(vm);

        env.objectPool.collectGarbage();

        switch (result) {
            .completed => return 0,
            .exhausted => {
                try std.io.getStdErr().writer().print("Execution exhausted after {} instructions!\n", .{
                    options.limit,
                });
                return 1;
            },
            .paused => {
                // continue execution here
                std.time.sleep(100); // sleep at least 100 ns and return control to scheduler
            },
        }
    }

    return 0;
}

fn compileFileToUnit(allocator: *std.mem.Allocator, fileName: []const u8) !lola.CompileUnit {
    const maxLength = 1 << 20; // 1 MB
    var source = blk: {
        var file = try std.fs.cwd().openFile(fileName, .{ .read = true, .write = false });
        defer file.close();

        break :blk try file.reader().readAllAlloc(std.heap.page_allocator, maxLength);
    };
    defer std.heap.page_allocator.free(source);

    var module: ModuleBuffer = undefined;

    if (!compile_lola_source(source.ptr, source.len, &module))
        return error.FailedToCompileModule;
    defer std.c.free(module.data);

    var moduleStream = std.io.fixedBufferStream(module.data[0..module.length]);

    return try lola.CompileUnit.loadFromStream(allocator, moduleStream.reader());
}

fn loadModuleFromFile(allocator: *std.mem.Allocator, fileName: []const u8) !lola.CompileUnit {
    var file = try std.fs.cwd().openFile(fileName, .{ .read = true, .write = false });
    defer file.close();

    return try lola.CompileUnit.loadFromStream(allocator, file.reader());
}

// fn new_main() anyerror!void {
//     var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
//     defer arena.deinit();

//     const allocator = &arena.allocator;

//     var cu = blk: {
//         var file = try std.fs.cwd().openFile("develop.lm", .{ .read = true, .write = false });
//         defer file.close();

//         var stream = file.inStream();
//         break :blk try lola.CompileUnit.loadFromStream(allocator, std.fs.File.InStream.Error, &stream.stream);
//     };
//     defer cu.deinit();

//     var stream = &std.io.getStdOut().outStream().stream;

//     try stream.write("metadata:\n");
//     try stream.print("\tcomment:         {}\n", .{cu.comment});
//     try stream.print("\tcode size:       {} bytes\n", .{cu.code.len});
//     try stream.print("\tnum globals:     {}\n", .{cu.globalCount});
//     try stream.print("\tnum temporaries: {}\n", .{cu.temporaryCount});
//     try stream.print("\tnum functions:   {}\n", .{cu.functions.len});
//     try stream.print("\tnum debug syms:  {}\n", .{cu.debugSymbols.len});

//     try stream.write("disassembly:\n");

//     try lola.disassemble(std.fs.File.OutStream.Error, stream, cu, lola.DisassemblerOptions{
//         .addressPrefix = true,
//     });

//     var counterAllocator = std.testing.LeakCountAllocator.init(std.heap.direct_allocator);
//     defer {
//         if (counterAllocator.count > 0) {
//             std.debug.warn("error - detected leaked allocations without matching free: {}\n", .{counterAllocator.count});
//         }
//     }

//     var env = try lola.Environment.init(std.heap.direct_allocator, &cu);
//     defer env.deinit();

//     try env.functions.putNoClobber("Print", lola.Function{
//         .syncUser = lola.UserFunction{
//             .context = undefined,
//             .destructor = null,
//             .call = struct {
//                 fn call(context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
//                     var stdout = &std.io.getStdOut().outStream().stream;
//                     for (args) |value, i| {
//                         if (i > 0)
//                             try stdout.write(" ");
//                         try stdout.print("{}", .{value});
//                     }
//                     try stdout.write("\n");
//                     return lola.Value.initVoid();
//                 }
//             }.call,
//         },
//     });

//     try env.functions.putNoClobber("Length", lola.Function{
//         .syncUser = lola.UserFunction{
//             .context = undefined,
//             .destructor = null,
//             .call = struct {
//                 fn call(context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
//                     if (args.len != 1)
//                         return error.InvalidArgs;
//                     return switch (args[0]) {
//                         .string => |str| lola.Value.initNumber(@intToFloat(f64, str.contents.len)),
//                         .array => |arr| lola.Value.initNumber(@intToFloat(f64, arr.contents.len)),
//                         else => error.TypeMismatch,
//                     };
//                 }
//             }.call,
//         },
//     });

//     try env.functions.putNoClobber("Sleep", lola.Function{
//         .asyncUser = lola.AsyncUserFunction{
//             .context = undefined,
//             .destructor = null,
//             .call = struct {
//                 fn call(call_context: lola.Context, args: []const lola.Value) anyerror!lola.AsyncFunctionCall {
//                     const ptr = try std.heap.direct_allocator.create(f64);

//                     if (args.len > 0) {
//                         ptr.* = try args[0].toNumber();
//                     } else {
//                         ptr.* = 1;
//                     }

//                     return lola.AsyncFunctionCall{
//                         .context = lola.Context.init(f64, ptr),
//                         .destructor = struct {
//                             fn dtor(exec_context: lola.Context) void {
//                                 std.heap.direct_allocator.destroy(exec_context.get(f64));
//                             }
//                         }.dtor,
//                         .execute = struct {
//                             fn execute(exec_context: lola.Context) anyerror!?lola.Value {
//                                 const count = exec_context.get(f64);

//                                 count.* -= 1;

//                                 if (count.* <= 0) {
//                                     return lola.Value.initVoid();
//                                 } else {
//                                     return null;
//                                 }
//                             }
//                         }.execute,
//                     };
//                 }
//             }.call,
//         },
//     });

//     var refValue = lola.Value.initNumber(23.0);

//     const MyObject = struct {
//         const Self = @This();

//         name: []const u8,

//         fn getMethod(self: *Self, name: []const u8) ?lola.Function {
//             std.debug.warn("getMethod({}, {})\n", .{
//                 self.name,
//                 name,
//             });
//             if (std.mem.eql(u8, name, "call")) {
//                 std.debug.warn("return call!\n", .{});
//                 return lola.Function{
//                     .syncUser = lola.UserFunction{
//                         .context = lola.Context.init(Self, self),
//                         .destructor = null,
//                         .call = struct {
//                             fn call(obj_context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
//                                 return lola.Value.initString(std.testing.allocator, obj_context.get(Self).name);
//                             }
//                         }.call,
//                     },
//                 };
//             }
//             return null;
//         }

//         fn destroyObject(self: Self) void {
//             std.debug.warn("destroyObject({})\n", .{
//                 self.name,
//             });
//         }
//     };

//     const LoLaStack = struct {
//         const Self = @This();

//         allocator: *std.mem.Allocator,
//         contents: std.ArrayList(lola.Value),

//         fn deinit(self: Self) void {
//             for (self.contents.toSliceConst()) |item| {
//                 item.deinit();
//             }
//             self.contents.deinit();
//         }

//         fn getMethod(self: *Self, name: []const u8) ?lola.Function {
//             if (std.mem.eql(u8, name, "Push")) {
//                 return lola.Function{
//                     .syncUser = lola.UserFunction{
//                         .context = lola.Context.init(Self, self),
//                         .destructor = null,
//                         .call = struct {
//                             fn call(obj_context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
//                                 for (args) |arg| {
//                                     const v = try arg.clone();
//                                     errdefer v.deinit();

//                                     try obj_context.get(Self).contents.append(v);
//                                 }
//                                 return lola.Value.initVoid();
//                             }
//                         }.call,
//                     },
//                 };
//             } else if (std.mem.eql(u8, name, "Pop")) {
//                 return lola.Function{
//                     .syncUser = lola.UserFunction{
//                         .context = lola.Context.init(Self, self),
//                         .destructor = null,
//                         .call = struct {
//                             fn call(obj_context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
//                                 var stack = obj_context.get(Self);
//                                 if (stack.contents.len > 0) {
//                                     return stack.contents.pop();
//                                 } else {
//                                     return lola.Value.initVoid();
//                                 }
//                             }
//                         }.call,
//                     },
//                 };
//             } else if (std.mem.eql(u8, name, "GetSize")) {
//                 return lola.Function{
//                     .syncUser = lola.UserFunction{
//                         .context = lola.Context.init(Self, self),
//                         .destructor = null,
//                         .call = struct {
//                             fn call(obj_context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
//                                 return lola.Value.initNumber(@intToFloat(f64, obj_context.get(Self).contents.len));
//                             }
//                         }.call,
//                     },
//                 };
//             }
//             return null;
//         }

//         fn destroyObject(self: Self) void {
//             self.deinit();
//             self.allocator.destroy(&self);
//             std.debug.warn("destroy stack\n", .{});
//         }
//     };

//     try env.functions.putNoClobber("CreateStack", lola.Function{
//         .syncUser = lola.UserFunction{
//             .context = lola.Context.init(lola.Environment, &env),
//             .destructor = null,
//             .call = struct {
//                 fn call(context: lola.Context, args: []const lola.Value) anyerror!lola.Value {
//                     var stack = try std.testing.allocator.create(LoLaStack);
//                     errdefer std.testing.allocator.destroy(stack);

//                     stack.* = LoLaStack{
//                         .allocator = std.testing.allocator,
//                         .contents = std.ArrayList(lola.Value).init(std.testing.allocator),
//                     };
//                     errdefer stack.deinit();

//                     const oid = try context.get(lola.Environment).objectPool.createObject(try lola.Object.init(.{stack}));

//                     return lola.Value.initObject(oid);
//                 }
//             }.call,
//         },
//     });

//     var obj1 = MyObject{
//         .name = "Object 1",
//     };
//     var obj2 = MyObject{
//         .name = "Object 2",
//     };

//     const objref1 = try env.objectPool.createObject(try lola.Object.init(.{&obj1}));
//     const objref2 = try env.objectPool.createObject(try lola.Object.init(.{&obj2}));

//     try env.objectPool.retainObject(objref1);
//     try env.objectPool.retainObject(objref2);

//     try env.namedGlobals.putNoClobber("valGlobal", lola.NamedGlobal.initStored(lola.Value.initNumber(42.0)));
//     try env.namedGlobals.putNoClobber("refGlobal", lola.NamedGlobal.initReferenced(&refValue));
//     try env.namedGlobals.putNoClobber("objGlobal1", lola.NamedGlobal.initStored(lola.Value.initObject(objref1)));
//     try env.namedGlobals.putNoClobber("objGlobal2", lola.NamedGlobal.initStored(lola.Value.initObject(objref2)));

//     // var smartCounter: u32 = 0;
//     // try env.namedGlobals.putNoClobber("smartCounter", lola.NamedGlobal.initSmart(lola.SmartGlobal.initRead(
//     //     lola.SmartGlobal.Context.init(u32, &smartCounter),
//     //     struct {
//     //         fn read(ctx: lola.SmartGlobal.Context) lola.Value {
//     //             const ptr = ctx.get(u32);
//     //             const res = ptr.*;
//     //             ptr.* += 1;
//     //             return lola.Value.initNumber(@intToFloat(f64, res));
//     //         }
//     //     }.read,
//     // )));

//     // try env.namedGlobals.putNoClobber("smartDumper", lola.NamedGlobal.initSmart(lola.SmartGlobal.initRead(
//     //     lola.SmartGlobal.Context.init(u32, &smartCounter),
//     //     struct {
//     //         fn read(ctx: lola.SmartGlobal.Context) lola.Value {
//     //             const ptr = ctx.get(u32);
//     //             const res = ptr.*;
//     //             ptr.* += 1;
//     //             return lola.Value.initNumber(@intToFloat(f64, res));
//     //         }
//     //     }.read,
//     // )));

//     var vm = try lola.VM.init(&counterAllocator.allocator, &env);
//     defer vm.deinit();

//     defer {
//         std.debug.warn("Stack:\n", .{});
//         for (vm.stack.toSliceConst()) |item, i| {
//             std.debug.warn("[{}]\t= {}\n", .{ i, item });
//         }
//     }

//     var timer = try std.time.Timer.start();

//     while (true) {
//         const instructionLimit = 100000.0;

//         var result = vm.execute(instructionLimit) catch |err| {
//             std.debug.warn("Failed to execute code: {}\n", .{err});
//             return err;
//         };

//         const lap = timer.lap();

//         const previous = env.objectPool.objects.size;

//         env.objectPool.clearUsageCounters();

//         try env.objectPool.walkEnvironment(env);
//         try env.objectPool.walkVM(vm);

//         env.objectPool.collectGarbage();

//         const now = env.objectPool.objects.size;

//         std.debug.warn("result: {}\tcollected {} objects\ttook {d:0<10.3} µs time → {d:0<10.3} µs/instr\n", .{
//             result,
//             previous - now,
//             @intToFloat(f64, lap) / 1000.0,
//             @intToFloat(f64, lap) / (1000.0 * instructionLimit),
//         });
//         if (result == .completed)
//             break;
//     }

//     for (env.scriptGlobals) |global, i| {
//         std.debug.warn("[{}]\t= {}\n", .{ i, global });
//     }

//     // std.debug.assert(refValue.eql(lola.Value.initVoid()));
// }
