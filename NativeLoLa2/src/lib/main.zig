const std = @import("std");

// Import modules to reduce file size
usingnamespace @import("value.zig");
usingnamespace @import("ir.zig");

/// A struct that allows decoding data from LoLa IR code.
const Decoder = struct {
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
        if (std.mem.indexOfScalar(u8, fullMem, 0)) |off| {
            return fullMem[0..off];
        } else {
            return fullMem;
        }
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
