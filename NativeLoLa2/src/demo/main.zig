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

    try lola.disassemble(std.fs.File.OutStream.Error, stream, cu, lola.DisassemblerOptions{});

    var env = try lola.Environment.init(std.heap.direct_allocator, &cu, lola.ObjectInterface.empty);
    defer env.deinit();

    var vm = try lola.VM.init(std.heap.direct_allocator, &env);
    defer vm.deinit();

    var result = vm.execute(1000) catch |err| {
        std.debug.warn("Failed to execute code: {}\n", .{err});

        std.debug.warn("Stack:\n", .{});

        for (vm.stack.toSliceConst()) |item, i| {
            std.debug.warn("[{}]\t= {}\n", .{ i, item });
        }

        return;
    };

    std.debug.warn("result: {}\n", .{result});

    for (env.scriptGlobals) |global, i| {
        std.debug.warn("[{}]\t= {}\n", .{ i, global });
    }
}
