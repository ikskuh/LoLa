const std = @import("std");
const lola = @import("lola");

fn writeHexDump(stream: var, data: []const u8, begin: usize, end: usize, width: usize) !void {
    var offset_hex = begin;
    while (offset_hex < begin + width) : (offset_hex += 1) {
        if (offset_hex < end) {
            try stream.print("{X:0>2} ", .{data[offset_hex]});
        } else {
            try stream.write("   ");
        }
    }

    try stream.write("|");
    var offset_bin = begin;
    while (offset_bin < begin + width) : (offset_bin += 1) {
        if (offset_bin < end) {
            if (std.ascii.isPrint(data[offset_bin])) {
                try stream.print("{c}", .{data[offset_bin]});
            } else {
                try stream.write(".");
            }
        } else {
            try stream.write(" ");
        }
    }
    try stream.write("|");
}

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

    try disassemble(allocator, std.fs.File.OutStream.Error, stream, cu, DisassemblerOptions{});
}

const DisassemblerOptions = struct {
    addressPrefix: bool = false,
    hexwidth: ?usize = null,
    labelOutput: bool = true,
    instructionOutput: bool = true,
};

pub fn disassemble(allocator: *std.mem.Allocator, comptime Error: type, stream: *std.io.OutStream(Error), cu: lola.CompileUnit, options: DisassemblerOptions) !void {
    var decoder = lola.Decoder.init(cu.code);

    const anyOutput = options.addressPrefix or options.labelOutput or options.instructionOutput or (options.hexwidth != null);

    if (options.addressPrefix)
        try stream.print("{X:0>6}\t", .{decoder.offset});
    if (options.labelOutput)
        try stream.write("<main>:\n");

    while (!decoder.isEof()) {
        if (options.labelOutput) {
            for (cu.functions) |fun| {
                if (fun.entryPoint == decoder.offset) {
                    if (options.addressPrefix)
                        try stream.print("{X:0>6}\t", .{decoder.offset});
                    try stream.print("{}:\n", .{fun.name});
                }
            }
        }
        if (options.addressPrefix)
            try stream.print("{X:0>6}\t", .{decoder.offset});

        const start = decoder.offset;
        const instr = try decoder.read(lola.Instruction);

        const formatted = switch (instr) {
            .push_str, .store_global_name, .load_global_name => blk: {
                const str = try decoder.readVarString();
                break :blk try std.fmt.allocPrint(allocator, "{} \"{}\"", .{ @tagName(instr), str });
            },
            .push_num => blk: {
                const val = try decoder.read(f64);
                break :blk try std.fmt.allocPrint(allocator, "{} \"{}\"", .{ @tagName(instr), val });
            },
            .call_fn, .call_obj => blk: {
                const str = try decoder.readVarString();
                const argc = try decoder.read(u8);
                break :blk try std.fmt.allocPrint(allocator, "{} \"{}\" {}", .{ @tagName(instr), str, argc });
            },
            .jmp, .jnf, .jif => blk: {
                const dest = try decoder.read(u32);
                break :blk try std.fmt.allocPrint(allocator, "{} {}", .{ @tagName(instr), dest });
            },
            .store_local, .load_local, .store_global_idx, .load_global_idx, .array_pack => blk: {
                const dest = try decoder.read(u16);
                break :blk try std.fmt.allocPrint(allocator, "{} {}", .{ @tagName(instr), dest });
            },
            else => blk: {
                break :blk try std.fmt.allocPrint(allocator, "{}", .{@tagName(instr)});
            },
        };
        defer allocator.free(formatted);

        const end = decoder.offset;

        if (options.hexwidth) |hw| {
            try writeHexDump(stream, decoder.data, start, end, hw);
        }

        if (options.instructionOutput) {
            try stream.write("\t");
            try stream.write(formatted);
        }

        if (anyOutput)
            try stream.write("\n");

        if (options.hexwidth) |hw| {
            var cursor = start + hw;
            var paddedEnd = start + 2 * hw;
            while (paddedEnd < end + hw) : (paddedEnd += hw) {
                if (options.addressPrefix)
                    try stream.print("{X:0>6}\t", .{cursor});
                try writeHexDump(stream, decoder.data, cursor, end, hw);
                cursor += hw;
                try stream.write("\n");
            }
        }
    }
}
