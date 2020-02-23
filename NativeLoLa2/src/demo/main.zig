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

    var vm = try lola.VM.init(&counterAllocator.allocator, &env);
    defer vm.deinit();

    defer {
        std.debug.warn("Stack:\n", .{});
        for (vm.stack.toSliceConst()) |item, i| {
            std.debug.warn("[{}]\t= {}\n", .{ i, item });
        }
    }

    var result = vm.execute(100) catch |err| {
        std.debug.warn("Failed to execute code: {}\n", .{err});
        return err;
    };

    std.debug.warn("result: {}\n", .{result});

    for (env.scriptGlobals) |global, i| {
        std.debug.warn("[{}]\t= {}\n", .{ i, global });
    }
}
