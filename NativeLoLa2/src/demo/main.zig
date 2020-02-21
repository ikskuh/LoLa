const std = @import("std");
const lola = @import("lola");

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var cu = blk: {
        var file = try std.fs.cwd().openFile("../Example/fib-iterative.lm", .{ .read = true, .write = false });
        defer file.close();

        var stream = file.inStream();
        break :blk try lola.CompileUnit.loadFromStream(allocator, std.fs.File.InStream.Error, &stream.stream);
    };
    defer cu.deinit();

    var stream = &std.io.getStdOut().outStream().stream;

    try lola.disassemble(allocator, std.fs.File.OutStream.Error, stream, cu, lola.DisassemblerOptions{});
}
