const std = @import("std");

usingnamespace @import("compile_unit.zig");
usingnamespace @import("decoder.zig");
usingnamespace @import("ir.zig");

pub const DisassemblerOptions = struct {
    /// Prefix each line of the disassembly with the hexadecimal address.
    addressPrefix: bool = false,

    /// If set, a hexdump with both hex- and ascii display will be emitted.
    /// Each line of text will contain `hexwidth` number of bytes.
    hexwidth: ?usize = null,

    /// If set to `true`, the output will contain a line with the
    /// name of function that starts at this offset. This option
    /// is set by default.
    labelOutput: bool = true,

    /// If set to `true`, the disassembled instruction will be emitted.
    /// This is set by default.
    instructionOutput: bool = true,
};

/// Disassembles a given compile unit into a text stream.
/// The output of the disassembler is adjustable to different formats.
/// If all output is disabled in the config, this function can also be used
/// to verify that a compile unit can be parsed completly without any problems.
pub fn disassemble(allocator: *std.mem.Allocator, comptime Error: type, stream: *std.io.OutStream(Error), cu: CompileUnit, options: DisassemblerOptions) !void {
    var decoder = Decoder.init(cu.code);

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
        const instr = try decoder.read(InstructionName);

        // TODO: Refactor to read(Instruction)

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
