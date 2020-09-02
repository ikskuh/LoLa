const std = @import("std");

const utility = @import("../common/utility.zig");

// Import modules to reduce file size
usingnamespace @import("value.zig");
usingnamespace @import("../common/ir.zig");
usingnamespace @import("../common/compile-unit.zig");

/// A struct that allows decoding data from LoLa IR code.
pub const Decoder = struct {
    const Self = @This();

    data: []const u8,

    // we are restricted to 4GB code size in the binary format, the decoder itself can use the same restriction
    offset: u32,

    pub fn init(source: []const u8) Self {
        return Self{
            .data = source,
            .offset = 0,
        };
    }

    pub fn isEof(self: Self) bool {
        return self.offset >= self.data.len;
    }

    pub fn readRaw(self: *Self, dest: []u8) !void {
        if (self.offset == self.data.len)
            return error.EndOfStream;
        if (self.offset + dest.len > self.data.len)
            return error.NotEnoughData;
        std.mem.copy(u8, dest, self.data[self.offset .. self.offset + dest.len]);
        self.offset += @intCast(u32, dest.len);
    }

    pub fn readBytes(self: *Self, comptime count: comptime_int) ![count]u8 {
        var data: [count]u8 = undefined;
        try self.readRaw(&data);
        return data;
    }

    /// Reads a value of the given type from the data stream.
    /// Allowed types are `u8`, `u16`, `u32`, `f64`, `Instruction`.
    pub fn read(self: *Self, comptime T: type) !T {
        if (T == Instruction) {
            return readInstruction(self);
        }

        const data = try self.readBytes(@sizeOf(T));
        switch (T) {
            u8, u16, u32 => return std.mem.readIntLittle(T, &data),
            f64 => return @bitCast(f64, data),
            InstructionName => return try std.meta.intToEnum(InstructionName, data[0]),
            else => @compileError("Unsupported type " ++ @typeName(T) ++ " for Decoder.read!"),
        }
    }

    /// Reads a variable-length string from the data stream.
    /// Note that the returned handle is only valid as long as Decoder.data is valid.
    pub fn readVarString(self: *Self) ![]const u8 {
        const len = try self.read(u16);
        if (self.offset + len > self.data.len)
            return error.NotEnoughData; // this is when a string tells you it's longer than the actual data storage.
        const string = self.data[self.offset .. self.offset + len];
        self.offset += len;
        return string;
    }

    /// Reads a fixed-length string from the data. The string may either be 0-terminated
    /// or use the available length completly.
    /// Note that the returned handle is only valid as long as Decoder.data is valid.
    pub fn readFixedString(self: *Self, comptime len: comptime_int) ![]const u8 {
        if (self.offset == self.data.len)
            return error.EndOfStream;
        if (self.offset + len > self.data.len)
            return error.NotEnoughData;
        const fullMem = self.data[self.offset .. self.offset + len];
        self.offset += len;
        return utility.clampFixedString(fullMem);
    }

    /// Reads a a full instruction from the source.
    /// This will provide full decoding and error checking.
    fn readInstruction(self: *Self) !Instruction {
        const instr = try self.read(InstructionName);
        inline for (std.meta.fields(Instruction)) |fld| {
            if (instr == @field(InstructionName, fld.name)) {
                if (fld.field_type == Instruction.Deprecated) {
                    return error.DeprecatedInstruction;
                } else if (fld.field_type == Instruction.NoArg) {
                    return @unionInit(Instruction, fld.name, .{});
                } else if (fld.field_type == Instruction.CallArg) {
                    const fun = self.readVarString() catch |err| return mapEndOfStreamToNotEnoughData(err);
                    const argc = self.read(u8) catch |err| return mapEndOfStreamToNotEnoughData(err);
                    return @unionInit(Instruction, fld.name, Instruction.CallArg{
                        .function = fun,
                        .argc = argc,
                    });
                } else {
                    const ValType = std.meta.fieldInfo(fld.field_type, "value").field_type;
                    if (ValType == []const u8) {
                        return @unionInit(Instruction, fld.name, fld.field_type{
                            .value = self.readVarString() catch |err| return mapEndOfStreamToNotEnoughData(err),
                        });
                    } else {
                        return @unionInit(Instruction, fld.name, fld.field_type{
                            .value = self.read(ValType) catch |err| return mapEndOfStreamToNotEnoughData(err),
                        });
                    }
                }
            }
        }
        unreachable;
    }

    fn mapEndOfStreamToNotEnoughData(err: anytype) @TypeOf(err) {
        return switch (err) {
            error.EndOfStream => error.NotEnoughData,
            else => err,
        };
    }
};

// zig fmt: off
const decoderTestBlob = [_]u8{
    1,2,3,       // "[3]u8"
    8,           // u8,
    16, 0,       // u16
    32, 0, 0, 0, // u32
    12,          // Instruction "add"
    5, 00, 'H', 'e', 'l', 'l', 'o', // String(*) "Hello"
    0x1F, 0x85, 0xEB, 0x51, 0xB8, 0x1E, 0x09, 0x40, // f64 = 3.14000000000000012434 == 0x40091EB851EB851F
    'B', 'y', 'e', 0, 0, 0, 0, 0, // String(8) "Bye"
};
// zig fmt: on

test "Decoder" {
    var decoder = Decoder.init(&decoderTestBlob);

    std.debug.assert(std.mem.eql(u8, &(try decoder.readBytes(3)), &[3]u8{ 1, 2, 3 }));
    std.debug.assert((try decoder.read(u8)) == 8);
    std.debug.assert((try decoder.read(u16)) == 16);
    std.debug.assert((try decoder.read(u32)) == 32);
    std.debug.assert((try decoder.read(InstructionName)) == .add);
    std.debug.assert(std.mem.eql(u8, try decoder.readVarString(), "Hello"));
    std.debug.assert((try decoder.read(f64)) == 3.14000000000000012434);
    std.debug.assert(std.mem.eql(u8, try decoder.readFixedString(8), "Bye"));

    if (decoder.readBytes(1)) |_| {
        std.debug.assert(false);
    } else |err| {
        std.debug.assert(err == error.EndOfStream);
    }
}

test "Decoder.NotEnoughData" {
    const blob = [_]u8{1};
    var decoder = Decoder.init(&blob);

    if (decoder.read(u16)) |_| {
        std.debug.assert(false);
    } else |err| {
        std.debug.assert(err == error.NotEnoughData);
    }
}

test "Decoder.NotEnoughData (string)" {
    const blob = [_]u8{ 1, 0 };
    var decoder = Decoder.init(&blob);

    if (decoder.readVarString()) |_| {
        std.debug.assert(false);
    } else |err| {
        std.debug.assert(err == error.NotEnoughData);
    }
}

test "Decoder.read(Instruction)" {
    const Pattern = struct {
        const ResultType = std.meta.declarationInfo(Decoder, "readInstruction").data.Fn.return_type;

        text: []const u8,
        instr: ResultType,

        fn isMatch(self: @This(), testee: ResultType) bool {
            if (self.instr) |a_p| {
                if (testee) |b_p| return eql(a_p, b_p) else |_| return false;
            } else |a_e| {
                if (testee) |_| return false else |b_e| return a_e == b_e;
            }
        }

        fn eql(a: Instruction, b: Instruction) bool {
            @setEvalBranchQuota(5000);
            const activeField = @as(InstructionName, a);
            if (activeField != @as(InstructionName, b))
                return false;
            inline for (std.meta.fields(InstructionName)) |fld| {
                if (activeField == @field(InstructionName, fld.name)) {
                    const FieldType = std.meta.fieldInfo(Instruction, fld.name).field_type;
                    const lhs = @field(a, fld.name);
                    const rhs = @field(b, fld.name);
                    if ((FieldType == Instruction.Deprecated) or (FieldType == Instruction.NoArg)) {
                        return true;
                    } else if (FieldType == Instruction.CallArg) {
                        return lhs.argc == rhs.argc and std.mem.eql(u8, lhs.function, rhs.function);
                    } else {
                        const ValType = std.meta.fieldInfo(FieldType, "value").field_type;
                        if (ValType == []const u8) {
                            return std.mem.eql(u8, lhs.value, rhs.value);
                        } else {
                            return lhs.value == rhs.value;
                        }
                    }
                }
            }
            unreachable;
        }
    };
    const patterns = [_]Pattern{
        .{ .text = "\x00", .instr = Instruction{ .nop = .{} } },
        .{ .text = "\x01", .instr = error.DeprecatedInstruction },
        .{ .text = "\x02", .instr = error.DeprecatedInstruction },
        .{ .text = "\x03", .instr = error.DeprecatedInstruction },
        .{ .text = "\x04\x01\x00X", .instr = Instruction{ .store_global_name = .{ .value = "X" } } },
        .{ .text = "\x05\x02\x00YZ", .instr = Instruction{ .load_global_name = .{ .value = "YZ" } } },
        .{ .text = "\x06\x03\x00ABC", .instr = Instruction{ .push_str = .{ .value = "ABC" } } },
        .{ .text = "\x07\x00\x00\x00\x00\x00\x00\x00\x00", .instr = Instruction{ .push_num = .{ .value = 0 } } },
        .{ .text = "\x08\x00\x10", .instr = Instruction{ .array_pack = .{ .value = 0x1000 } } },
        .{ .text = "\x09\x01\x00x\x01", .instr = Instruction{ .call_fn = .{ .function = "x", .argc = 1 } } },
        .{ .text = "\x0A\x02\x00yz\x03", .instr = Instruction{ .call_obj = .{ .function = "yz", .argc = 3 } } },
        .{ .text = "\x0B", .instr = Instruction{ .pop = .{} } },
        .{ .text = "\x0C", .instr = Instruction{ .add = .{} } },
        .{ .text = "\x0D", .instr = Instruction{ .sub = .{} } },
        .{ .text = "\x0E", .instr = Instruction{ .mul = .{} } },
        .{ .text = "\x0F", .instr = Instruction{ .div = .{} } },
        .{ .text = "\x10", .instr = Instruction{ .mod = .{} } },
        .{ .text = "\x11", .instr = Instruction{ .bool_and = .{} } },
        .{ .text = "\x12", .instr = Instruction{ .bool_or = .{} } },
        .{ .text = "\x13", .instr = Instruction{ .bool_not = .{} } },
        .{ .text = "\x14", .instr = Instruction{ .negate = .{} } },
        .{ .text = "\x15", .instr = Instruction{ .eq = .{} } },
        .{ .text = "\x16", .instr = Instruction{ .neq = .{} } },
        .{ .text = "\x17", .instr = Instruction{ .less_eq = .{} } },
        .{ .text = "\x18", .instr = Instruction{ .greater_eq = .{} } },
        .{ .text = "\x19", .instr = Instruction{ .less = .{} } },
        .{ .text = "\x1A", .instr = Instruction{ .greater = .{} } },
        .{ .text = "\x1B\x00\x11\x22\x33", .instr = Instruction{ .jmp = .{ .value = 0x33221100 } } },
        .{ .text = "\x1C\x44\x33\x22\x11", .instr = Instruction{ .jnf = .{ .value = 0x11223344 } } },
        .{ .text = "\x1D", .instr = Instruction{ .iter_make = .{} } },
        .{ .text = "\x1E", .instr = Instruction{ .iter_next = .{} } },
        .{ .text = "\x1F", .instr = Instruction{ .array_store = .{} } },
        .{ .text = "\x20", .instr = Instruction{ .array_load = .{} } },
        .{ .text = "\x21", .instr = Instruction{ .ret = .{} } },
        .{ .text = "\x22\xDE\xBA", .instr = Instruction{ .store_local = .{ .value = 0xBADE } } },
        .{ .text = "\x23\xFE\xAF", .instr = Instruction{ .load_local = .{ .value = 0xAFFE } } },
        .{ .text = "\x25", .instr = Instruction{ .retval = .{} } },
        .{ .text = "\x26\x00\x12\x34\x56", .instr = Instruction{ .jif = .{ .value = 0x56341200 } } },
        .{ .text = "\x27\x34\x12", .instr = Instruction{ .store_global_idx = .{ .value = 0x1234 } } },
        .{ .text = "\x28\x21\x43", .instr = Instruction{ .load_global_idx = .{ .value = 0x4321 } } },
        .{ .text = "\x29", .instr = Instruction{ .push_true = .{} } },
        .{ .text = "\x2A", .instr = Instruction{ .push_false = .{} } },
        .{ .text = "\x2B", .instr = Instruction{ .push_void = .{} } },
        .{ .text = "", .instr = error.EndOfStream },
        .{ .text = "\x26", .instr = error.NotEnoughData },
        .{ .text = "\x09\xFF", .instr = error.NotEnoughData },
        .{ .text = "\x26\x00\x00", .instr = error.NotEnoughData },
        .{ .text = "\x09\xFF\xFF", .instr = error.NotEnoughData },
    };
    for (patterns) |pattern| {
        var decoder = Decoder.init(pattern.text);
        const instruction = decoder.read(Instruction);
        if (!pattern.isMatch(instruction)) {
            std.debug.warn("expected {}, got {}\n", .{ pattern.instr, instruction });
            std.debug.assert(false);
        }
    }
}
