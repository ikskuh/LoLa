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

    try lola.disassemble(std.fs.File.OutStream.Error, stream, cu, lola.DisassemblerOptions{
        .addressPrefix = true,
    });

    var counterAllocator = std.testing.LeakCountAllocator.init(std.heap.direct_allocator);
    defer {
        if (counterAllocator.count > 0) {
            std.debug.warn("error - detected leaked allocations without matching free: {}\n", .{counterAllocator.count});
        }
    }

    var env = try lola.Environment.init(std.heap.direct_allocator, &cu, lola.ObjectInterface.empty);
    defer env.deinit();

    try env.functions.putNoClobber("Print", lola.Function{
        .syncUser = lola.UserFunction{
            .context = undefined,
            .destructor = null,
            .call = struct {
                fn call(context: []const u8, args: []const lola.Value) anyerror!lola.Value {
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

    try env.functions.putNoClobber("Sleep", lola.Function{
        .asyncUser = lola.AsyncUserFunction{
            .context = undefined,
            .destructor = null,
            .call = struct {
                fn call(call_context: []const u8, args: []const lola.Value) anyerror!lola.AsyncFunctionCall {
                    const ptr = try std.heap.direct_allocator.create(f64);

                    if (args.len > 0) {
                        ptr.* = try args[0].toNumber();
                    } else {
                        ptr.* = 1;
                    }

                    return lola.AsyncFunctionCall{
                        .context = std.mem.asBytes(ptr),
                        .destructor = struct {
                            fn dtor(exec_context: []u8) void {
                                std.heap.direct_allocator.destroy(@ptrCast(*f64, @alignCast(@alignOf(f64), exec_context.ptr)));
                            }
                        }.dtor,
                        .execute = struct {
                            fn execute(exec_context: []u8) anyerror!?lola.Value {
                                const count = @ptrCast(*f64, @alignCast(@alignOf(f64), exec_context.ptr));

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

    try env.namedGlobals.putNoClobber("valGlobal", lola.NamedGlobal.initStored(lola.Value.initNumber(42.0)));
    try env.namedGlobals.putNoClobber("refGlobal", lola.NamedGlobal.initReferenced(&refValue));

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
        var result = vm.execute(100) catch |err| {
            std.debug.warn("Failed to execute code: {}\n", .{err});
            return err;
        };
        std.debug.warn("result: {}\n", .{result});
        if (result == .completed)
            break;
    }

    for (env.scriptGlobals) |global, i| {
        std.debug.warn("[{}]\t= {}\n", .{ i, global });
    }

    // std.debug.assert(refValue.eql(lola.Value.initVoid()));
}
