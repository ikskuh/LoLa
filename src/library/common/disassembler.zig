const std = @import("std");

const CompileUnit = @import("CompileUnit.zig");
const Decoder = @import("Decoder.zig");
const ir = @import("ir.zig");

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
pub fn disassemble(stream: *std.Io.Writer, cu: CompileUnit, options: DisassemblerOptions) !void {
    var decoder = Decoder.init(cu.code);

    const anyOutput = options.addressPrefix or options.labelOutput or options.instructionOutput or (options.hexwidth != null);

    if (options.addressPrefix)
        try stream.print("{X:0>6}\t", .{decoder.offset});
    if (options.labelOutput)
        try stream.writeAll("<main>:\n");

    while (!decoder.isEof()) {
        if (options.labelOutput) {
            for (cu.functions) |fun| {
                if (fun.entryPoint == decoder.offset) {
                    if (options.addressPrefix)
                        try stream.print("{X:0>6}\t", .{decoder.offset});
                    try stream.print("{s}:\n", .{fun.name});
                }
            }
        }
        if (options.addressPrefix)
            try stream.print("{X:0>6}\t", .{decoder.offset});

        const start = decoder.offset;
        const instr = try decoder.read(ir.Instruction);
        const end = decoder.offset;

        if (options.hexwidth) |hw| {
            try writeHexDump(stream, decoder.data, start, end, hw);
        }

        if (options.instructionOutput) {
            try stream.writeAll("\t");
            try stream.writeAll(@tagName(@as(ir.InstructionName, instr)));

            inline for (std.meta.fields(ir.Instruction)) |fld| {
                const instr_name = @field(ir.InstructionName, fld.name);
                if (instr == instr_name) {
                    if (fld.type == ir.Instruction.Deprecated) {
                        // no-op
                    } else if (fld.type == ir.Instruction.NoArg) {
                        // no-op
                    } else if (fld.type == ir.Instruction.CallArg) {
                        const args = @field(instr, fld.name);
                        try stream.print(" {s} {d}", .{ args.function, args.argc });
                    } else {
                        if (@TypeOf(@field(instr, fld.name).value) == f64) {
                            try stream.print(" {d}", .{@field(instr, fld.name).value});
                        } else if (instr_name == .jif or instr_name == .jmp or instr_name == .jnf) {
                            try stream.print(" 0x{X}", .{@field(instr, fld.name).value});
                        } else {
                            try stream.print(" {any}", .{@field(instr, fld.name).value});
                        }
                    }
                }
            }
        }

        if (anyOutput)
            try stream.writeAll("\n");

        if (options.hexwidth) |hw| {
            var cursor = start + hw;
            var paddedEnd = start + 2 * hw;
            while (paddedEnd < end + hw) : (paddedEnd += hw) {
                if (options.addressPrefix)
                    try stream.print("{X:0>6}\t", .{cursor});
                try writeHexDump(stream, decoder.data, cursor, end, hw);
                cursor += hw;
                try stream.writeAll("\n");
            }
        }
    }
}

fn writeHexDump(stream: anytype, data: []const u8, begin: usize, end: usize, width: usize) !void {
    var offset_hex = begin;
    while (offset_hex < begin + width) : (offset_hex += 1) {
        if (offset_hex < end) {
            try stream.print("{X:0>2} ", .{data[offset_hex]});
        } else {
            try stream.writeAll("   ");
        }
    }

    try stream.writeAll("|");
    var offset_bin = begin;
    while (offset_bin < begin + width) : (offset_bin += 1) {
        if (offset_bin < end) {
            if (std.ascii.isPrint(data[offset_bin])) {
                try stream.print("{c}", .{data[offset_bin]});
            } else {
                try stream.writeAll(".");
            }
        } else {
            try stream.writeAll(" ");
        }
    }
    try stream.writeAll("|");
}

test "disassemble" {
    // dummy test
    _ = disassemble;
}
