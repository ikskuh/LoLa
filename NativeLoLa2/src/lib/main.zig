const std = @import("std");

// Import modules to reduce file size
usingnamespace @import("value.zig");
usingnamespace @import("ir.zig");

/// A compiled piece of code, provides the building blocks for
/// an environment. Note that a compile unit must be instantiated
/// into an environment to be executed.
pub const CompileUnit = struct {
    const Self = @This();

    /// Description of a script function.
    pub const Function = struct {
        name: []u8,
        entryPoint: u32,
        localCount: u16,
    };

    /// A mapping of which code portion belongs to which
    /// line in the source code.
    /// Lines are valid from offset until the next available symbol.
    pub const DebugSymbol = struct {
        /// Offset of the symbol from the start of the compiled code.
        offset: u32,

        /// The line number, starting at 1.
        sourceLine: u32,

        /// The offset into the line, starting at 1.
        sourceColumn: u16,
    };

    arena: std.heap.ArenaAllocator,
    comment: []u8,
    globalCount: u16,
    code: []u8,
    functions: []Function,
    debugSymbols: []DebugSymbol,

    /// Loads a compile unit from a data stream.
    fn loadFromStream(allocator: *std.mem.Allocator, comptime Error: type, stream: *std.io.InStream(Error)) !Self {
        // var inStream = file.getInStream();
        // var stream = &inStream.stream;
        var header: [8]u8 = undefined;
        try stream.readNoEof(&header);
        if (!std.mem.eql(u8, &header, "LoLa\xB9\x40\x80\x5A"))
            return error.InvalidFormat;
        const version = try stream.readIntLittle(u32);
        if (version != 1)
            return error.UnsupportedVersion;

        var comment: [256]u8 = undefined;
        try stream.readNoEof(&comment);

        var unit = Self{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .globalCount = undefined,
            .code = undefined,
            .functions = undefined,
            .debugSymbols = undefined,
            .comment = undefined,
        };
        errdefer unit.arena.deinit();

        unit.comment = try std.mem.dupe(&unit.arena.allocator, u8, clampFixedString(&comment));

        unit.globalCount = try stream.readIntLittle(u16);

        const functionCount = try stream.readIntLittle(u16);
        const codeSize = try stream.readIntLittle(u32);
        const numSymbols = try stream.readIntLittle(u32);

        unit.functions = try unit.arena.allocator.alloc(Function, functionCount);
        unit.code = try unit.arena.allocator.alloc(u8, codeSize);
        unit.debugSymbols = try unit.arena.allocator.alloc(DebugSymbol, numSymbols);

        for (unit.functions) |*fun| {
            var name: [128]u8 = undefined;
            try stream.readNoEof(&name);

            const entryPoint = try stream.readIntLittle(u32);
            const localCount = try stream.readIntLittle(u16);

            fun.* = Function{
                .name = try std.mem.dupe(&unit.arena.allocator, u8, clampFixedString(&name)),
                .entryPoint = entryPoint,
                .localCount = localCount,
            };
        }

        try stream.readNoEof(unit.code);

        for (unit.debugSymbols) |*sym| {
            const offset = try stream.readIntLittle(u32);
            const sourceLine = try stream.readIntLittle(u32);
            const sourceColumn = try stream.readIntLittle(u16);
            sym.* = DebugSymbol{
                .offset = offset,
                .sourceLine = sourceLine,
                .sourceColumn = sourceColumn,
            };
        }

        return unit;
    }

    /// Saves a compile unit to a data stream.
    fn saveToStream(self: Self, comptime Error: type, stream: *std.io.OutStream(Error)) !void {
        try stream.write("LoLa\xB9\x40\x80\x5A");
        try stream.writeIntLittle(u32, 1);
        try stream.write("Made with NativeLola.zig!" ++ ("\x00" ** (256 - 25)));
        try stream.writeIntLittle(u16, self.globalCount);
        try stream.writeIntLittle(u16, @intCast(u16, self.functions.len));
        try stream.writeIntLittle(u32, @intCast(u32, self.code.len));
        try stream.writeIntLittle(u32, @intCast(u32, self.debugSymbols.len));
        for (self.functions) |fun| {
            try stream.write(fun.name);
            try stream.writeByteNTimes(0, 128 - fun.name.len);
            try stream.writeIntNative(u32, fun.entryPoint);
            try stream.writeIntNative(u16, fun.localCount);
        }
        try stream.write(self.code);
        for (self.debugSymbols) |sym| {
            try stream.writeIntNative(u32, sym.offset);
            try stream.writeIntNative(u32, sym.sourceLine);
            try stream.writeIntNative(u16, sym.sourceColumn);
        }
    }

    fn deinit(self: Self) void {
        self.arena.deinit();
    }
};

test "CompileUnit.loadFromStream" {
    const serializedCompileUnit = "" // SoT
        ++ "LoLa\xB9\x40\x80\x5A" // Header
        ++ "\x01\x00\x00\x00" // Version
        ++ "Made with NativeLola.zig!" ++ ("\x00" ** (256 - 25)) // Comment
        ++ "\x03\x00" // globalCount
        ++ "\x02\x00" // functionCount
        ++ "\x05\x00\x00\x00" // codeSize
        ++ "\x03\x00\x00\x00" // numSymbols
        ++ "Function1" ++ ("\x00" ** (128 - 9)) // Name
        ++ "\x00\x00\x00\x00" // entryPoint
        ++ "\x01\x00" // localCount
        ++ "Function2" ++ ("\x00" ** (128 - 9)) // Name
        ++ "\x10\x10\x00\x00" // entryPoint
        ++ "\x02\x00" // localCount
        ++ "Hello" // code
        ++ "\x00\x00\x00\x00" ++ "\x01\x00\x00\x00" ++ "\x01\x00" // dbgSym1
        ++ "\x02\x00\x00\x00" ++ "\x02\x00\x00\x00" ++ "\x04\x00" // dbgSym2
        ++ "\x04\x00\x00\x00" ++ "\x03\x00\x00\x00" ++ "\x08\x00" // dbgSym3
        ;

    var sliceInStream = std.io.SliceInStream.init(serializedCompileUnit);

    const cu = try CompileUnit.loadFromStream(std.testing.allocator, std.io.SliceInStream.Error, &sliceInStream.stream);
    defer cu.deinit();

    std.debug.assert(std.mem.eql(u8, cu.comment, "Made with NativeLola.zig!"));
    std.debug.assert(cu.globalCount == 3);
    std.debug.assert(std.mem.eql(u8, cu.code, "Hello"));
    std.debug.assert(cu.functions.len == 2);
    std.debug.assert(cu.debugSymbols.len == 3);

    std.debug.assert(std.mem.eql(u8, cu.functions[0].name, "Function1"));
    std.debug.assert(cu.functions[0].entryPoint == 0x00000000);
    std.debug.assert(cu.functions[0].localCount == 1);

    std.debug.assert(std.mem.eql(u8, cu.functions[1].name, "Function2"));
    std.debug.assert(cu.functions[1].entryPoint == 0x00001010);
    std.debug.assert(cu.functions[1].localCount == 2);

    std.debug.assert(cu.debugSymbols[0].offset == 0);
    std.debug.assert(cu.debugSymbols[0].sourceLine == 1);
    std.debug.assert(cu.debugSymbols[0].sourceColumn == 1);

    std.debug.assert(cu.debugSymbols[1].offset == 2);
    std.debug.assert(cu.debugSymbols[1].sourceLine == 2);
    std.debug.assert(cu.debugSymbols[1].sourceColumn == 4);

    std.debug.assert(cu.debugSymbols[2].offset == 4);
    std.debug.assert(cu.debugSymbols[2].sourceLine == 3);
    std.debug.assert(cu.debugSymbols[2].sourceColumn == 8);

    var storage: [serializedCompileUnit.len]u8 = undefined;
    var sliceOutStream = std.io.SliceOutStream.init(&storage);

    try cu.saveToStream(std.io.SliceOutStream.Error, &sliceOutStream.stream);

    std.debug.assert(sliceOutStream.getWritten().len == serializedCompileUnit.len);

    std.debug.assert(std.mem.eql(u8, sliceOutStream.getWritten(), serializedCompileUnit));
}

/// An execution environment provides all needed
/// data to execute a compiled piece of code.
/// It stores its global variables, available functions
/// and available features.
pub const Environment = struct {};

/// A struct that allows decoding data from LoLa IR code.
pub const Decoder = struct {
    const Self = @This();

    data: []const u8,
    offset: usize,

    pub fn init(source: []const u8) Self {
        return Self{
            .data = source,
            .offset = 0,
        };
    }

    pub fn readRaw(self: *Self, dest: []u8) !void {
        if (self.offset == self.data.len)
            return error.EndOfStream;
        if (self.offset + dest.len > self.data.len)
            return error.NotEnoughData;
        std.mem.copy(u8, dest, self.data[self.offset .. self.offset + dest.len]);
        self.offset += dest.len;
    }

    pub fn readBytes(self: *Self, comptime count: comptime_int) ![count]u8 {
        var data: [count]u8 = undefined;
        try self.readRaw(&data);
        return data;
    }

    /// Reads a value of the given type from the data stream.
    /// Allowed types are `u8`, `u16`, `u32`, `f64`, `Instruction`.
    fn read(self: *Self, comptime T: type) !T {
        const data = try self.readBytes(@sizeOf(T));
        switch (T) {
            u8, u16, u32 => return std.mem.readIntLittle(T, &data),
            f64 => return @bitCast(f64, data),
            Instruction => return @intToEnum(Instruction, data[0]),
            else => @compileError("Unsupported type " ++ @typeName(T) ++ " for Decoder.read!"),
        }
    }

    /// Reads a variable-length string from the data stream.
    /// Note that the returned handle is only valid as long as Decoder.data is valid.
    pub fn readVarString(self: *Self) ![]const u8 {
        const len = try self.read(u16);
        if (self.offset + len > self.data.len)
            return error.CorruptedData; // this is when a string tells you it's longer than the actual data storage.
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
        return clampFixedString(fullMem);
    }
};

fn clampFixedString(str: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, str, 0)) |off| {
        return str[0..off];
    } else {
        return str;
    }
}

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
    std.debug.assert((try decoder.read(Instruction)) == .add);
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

test "Decoder.CorruptedData" {
    const blob = [_]u8{ 1, 0 };
    var decoder = Decoder.init(&blob);

    if (decoder.readVarString()) |_| {
        std.debug.assert(false);
    } else |err| {
        std.debug.assert(err == error.CorruptedData);
    }
}
