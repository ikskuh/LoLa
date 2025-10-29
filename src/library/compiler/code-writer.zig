const std = @import("std");

const Instruction = @import("../common/ir.zig").Instruction;
const InstructionName = @import("../common/ir.zig").InstructionName;

/// A handle to a location in source code.
/// This handle is created by a `CodeWriter` and only that code writer
/// knows where this label is located in memory (or if it is yet to be defined).
pub const Label = enum(u32) { _ };

/// A append-only data structure that allows emission of data and instructions to create
/// LoLa byte code.
pub const CodeWriter = struct {
    const Self = @This();

    const Loop = struct { breakLabel: Label, continueLabel: Label };
    const Patch = struct { label: Label, offset: u32 };

    /// The bytecode that was already emitted.
    code: std.ArrayList(u8),

    /// Used as a stack of loops. Each loop has a break position and a continue position,
    /// which can be emitted by calling emitBreak or emitContinue. This allows nesting loops
    /// and emitting the right loop targets without passing the context around in code generation.
    loops: std.ArrayList(Loop),

    /// Stores a list of forward references for labels. This is required
    /// when a call to `emitLabel` happens before `defineLabel` is called.
    /// This list is empty when all emitted label references are well-defined.
    patches: std.ArrayList(Patch),

    /// Stores the offset for every defined label.
    labels: std.AutoHashMap(Label, u32),

    next_label: u32 = 0,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .code = std.ArrayList(u8).empty,
            .loops = std.ArrayList(Loop).empty,
            .patches = std.ArrayList(Patch).empty,
            .labels = std.AutoHashMap(Label, u32).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.code.deinit(self.allocator);
        self.loops.deinit(self.allocator);
        self.patches.deinit(self.allocator);
        self.labels.deinit();

        self.* = undefined;
    }

    /// Finalizes the code generation process and returns the generated code.
    /// The returned memory is owned by the caller and was allocated with the allocator passed into `init`.
    pub fn finalize(self: *Self) ![]u8 {
        if (self.loops.items.len != 0)
            return error.InvalidCode;
        if (self.patches.items.len != 0)
            return error.InvalidCode;

        self.loops.shrinkAndFree(self.allocator, 0);
        self.patches.shrinkAndFree(self.allocator, 0);
        self.labels.clearAndFree();
        return self.code.toOwnedSlice(self.allocator);
    }

    /// Creates a new label identifier. This only returns a new handle, it does
    /// not emit any code or modify data structures.
    pub fn createLabel(self: *Self) !Label {
        if (self.next_label == std.math.maxInt(u32))
            return error.TooManyLabels;
        const id = @as(Label, @enumFromInt(self.next_label));
        self.next_label += 1;
        return id;
    }

    /// Defines the location a label references. This must be called exactly once for a label.
    /// Calling it more than once is a error, the same as calling it never.
    /// Defining a label will patch all forward references in the `code`, removing the need to
    /// store patches for later.
    pub fn defineLabel(self: *Self, lbl: Label) !void {
        const item = try self.labels.getOrPut(lbl);
        if (item.found_existing)
            return error.LabelAlreadyDefined;
        item.value_ptr.* = @as(u32, @intCast(self.code.items.len));

        // resolve all forward references to this label, so we
        // have a empty patch list when every referenced label was also defined.

        var i: usize = 0;
        while (i < self.patches.items.len) {
            const patch = self.patches.items[i];
            if (patch.label == lbl) {
                std.mem.writeInt(u32, self.code.items[patch.offset..][0..4], item.value_ptr.*, .little);
                _ = self.patches.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Combination of createLabel and defineLabel, is provided as a convenience function.
    pub fn createAndDefineLabel(self: *Self) !Label {
        const lbl = try self.createLabel();
        try self.defineLabel(lbl);
        return lbl;
    }

    /// Pushes a new loop construct.
    /// `breakLabel` is a label that is jumped to when a `break` instruction is emitted. This is usually the end of the loop.
    /// `continueLabel` is a label that is jumped to when a `continue` instruction is emitted. This is usually the start of the loop.
    pub fn pushLoop(self: *Self, breakLabel: Label, continueLabel: Label) !void {
        try self.loops.append(self.allocator, Loop{
            .breakLabel = breakLabel,
            .continueLabel = continueLabel,
        });
    }

    /// Pops a loop from the stack.
    pub fn popLoop(self: *Self) void {
        std.debug.assert(self.loops.items.len > 0);
        _ = self.loops.pop();
    }

    /// emits raw data
    pub fn emitRaw(self: *Self, data: []const u8) !void {
        if (self.code.items.len + data.len > std.math.maxInt(u32))
            return error.OutOfMemory;

        try self.code.writer(self.allocator).writeAll(data);
    }

    /// Emits a label and marks a patch position if necessary
    pub fn emitLabel(self: *Self, label: Label) !void {
        if (self.labels.get(label)) |offset| {
            try self.emitU32(offset);
        } else {
            try self.patches.append(self.allocator, Patch{
                .label = label,
                .offset = @as(u32, @intCast(self.code.items.len)),
            });
            try self.emitU32(0xFFFFFFFF);
        }
    }

    /// Emits a raw instruction name without the corresponding instruction arguments.
    pub fn emitInstructionName(self: *Self, name: InstructionName) !void {
        try self.emitU8(@intFromEnum(name));
    }

    pub fn emitInstruction(self: *Self, instr: Instruction) !void {
        try self.emitInstructionName(instr);
        inline for (std.meta.fields(Instruction)) |fld| {
            if (instr == @field(InstructionName, fld.name)) {
                const value = @field(instr, fld.name);
                if (fld.type == Instruction.Deprecated) {
                    @panic("called emitInstruction with a deprecated instruction!"); // this is a API violation
                } else if (fld.type == Instruction.NoArg) {
                    // It's enough to emit the instruction name
                    return;
                } else if (fld.type == Instruction.CallArg) {
                    try self.emitString(value.function);
                    try self.emitU8(value.argc);
                    return;
                } else {
                    const ValType = std.meta.fieldInfo(fld.type, .value).type;
                    switch (ValType) {
                        []const u8 => try self.emitString(value.value),
                        u8 => try self.emitU8(value.value),
                        u16 => try self.emitU16(value.value),
                        u32 => try self.emitU32(value.value),
                        f64 => try self.emitNumber(value.value),
                        else => @compileError("Unsupported encoding: " ++ @typeName(ValType)),
                    }
                    return;
                }
            }
        }
        unreachable;
    }

    fn emitNumber(self: *Self, val: f64) !void {
        try self.emitRaw(std.mem.asBytes(&val));
    }

    /// Encodes a variable-length string with a max. length of 0 … 65535 characters.
    pub fn emitString(self: *Self, val: []const u8) !void {
        try self.emitU16(std.math.cast(u16, val.len) orelse return error.Overflow);
        try self.emitRaw(val);
    }

    fn emitInteger(self: *Self, comptime T: type, val: T) !void {
        var buf: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &buf, val, .little);
        try self.emitRaw(&buf);
    }

    /// Emits a unsigned 32 bit integer, encoded little endian.
    pub fn emitU8(self: *Self, val: u8) !void {
        try self.emitInteger(u8, val);
    }

    /// Emits a unsigned 32 bit integer, encoded little endian.
    pub fn emitU16(self: *Self, val: u16) !void {
        try self.emitInteger(u16, val);
    }

    /// Emits a unsigned 32 bit integer, encoded little endian.
    pub fn emitU32(self: *Self, val: u32) !void {
        try self.emitInteger(u32, val);
    }

    pub fn emitBreak(self: *Self) !void {
        if (self.loops.items.len > 0) {
            const loop = self.loops.items[self.loops.items.len - 1];
            try self.emitInstructionName(.jmp);
            try self.emitLabel(loop.breakLabel);
        } else {
            return error.NotInLoop;
        }
    }

    pub fn emitContinue(self: *Self) !void {
        if (self.loops.items.len > 0) {
            const loop = self.loops.items[self.loops.items.len - 1];
            try self.emitInstructionName(.jmp);
            try self.emitLabel(loop.continueLabel);
        } else {
            return error.NotInLoop;
        }
    }
};

test "empty code generation" {
    var writer = CodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    const mem = try writer.finalize();
    defer std.testing.allocator.free(mem);

    try std.testing.expectEqualSlices(u8, "", mem);
}

test "emitting primitive values" {
    var writer = CodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    try writer.emitU32(0x44332211);
    try writer.emitU16(0x6655);
    try writer.emitU8(0x77);
    try writer.emitInstructionName(.jmp);

    const mem = try writer.finalize();
    defer std.testing.allocator.free(mem);

    try std.testing.expectEqualSlices(u8, "\x11\x22\x33\x44\x55\x66\x77\x1B", mem);
}

test "emitting variable-width strings" {
    var writer = CodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    try writer.emitString("Hello");

    const mem = try writer.finalize();
    defer std.testing.allocator.free(mem);

    try std.testing.expectEqualSlices(u8, "\x05\x00Hello", mem);
}

test "label handling" {
    var writer = CodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    const label = try writer.createLabel();

    try writer.emitLabel(label); // tests the patch path

    try writer.defineLabel(label); // tests label insertion

    try writer.emitLabel(label); // tests the fast-forward path

    const mem = try writer.finalize();
    defer std.testing.allocator.free(mem);

    try std.testing.expectEqualSlices(u8, "\x04\x00\x00\x00\x04\x00\x00\x00", mem);
}

test "label creation" {
    var writer = CodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    const label1 = try writer.createLabel();
    const label2 = try writer.createLabel();
    const label3 = try writer.createLabel();

    try std.testing.expect(label1 != label2);
    try std.testing.expect(label1 != label3);
    try std.testing.expect(label2 != label3);
}

test "loop creation, break and continue emission" {
    var writer = CodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    const label_start = try writer.createLabel();
    const label_end = try writer.createLabel();

    try std.testing.expectError(error.NotInLoop, writer.emitBreak());
    try std.testing.expectError(error.NotInLoop, writer.emitContinue());

    try writer.emitRaw("A");

    try writer.pushLoop(label_end, label_start);

    try writer.emitRaw("B");

    try writer.defineLabel(label_start);

    try writer.emitRaw("C");

    try writer.emitBreak();

    try writer.emitRaw("D");

    try writer.emitContinue();

    try writer.emitRaw("E");

    try writer.defineLabel(label_end);

    try writer.emitRaw("F");

    writer.popLoop();

    try std.testing.expectError(error.NotInLoop, writer.emitBreak());
    try std.testing.expectError(error.NotInLoop, writer.emitContinue());

    const mem = try writer.finalize();
    defer std.testing.allocator.free(mem);

    try std.testing.expectEqualSlices(u8, "ABC\x1B\x0F\x00\x00\x00D\x1B\x02\x00\x00\x00EF", mem);
}

test "emitting numeric value" {
    var writer = CodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    try writer.emitNumber(0.0);

    const mem = try writer.finalize();
    defer std.testing.allocator.free(mem);

    try std.testing.expectEqualSlices(u8, "\x00\x00\x00\x00\x00\x00\x00\x00", mem);
}

test "instruction emission" {
    var writer = CodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    // tests a NoArg instruction
    try writer.emitInstruction(Instruction{
        .push_void = .{},
    });

    // tests a SingleArg([]const u8) instruction
    try writer.emitInstruction(Instruction{
        .push_str = .{ .value = "abc" },
    });

    // tests a SingleArg(f64) instruction
    try writer.emitInstruction(Instruction{
        .push_num = .{ .value = 0.0000 },
    });

    // tests a SingleArg(u32) instruction
    try writer.emitInstruction(Instruction{
        .jmp = .{ .value = 0x44332211 },
    });

    // tests a SingleArg(u16) instruction
    try writer.emitInstruction(Instruction{
        .store_local = .{ .value = 0xBEEF },
    });

    const mem = try writer.finalize();
    defer std.testing.allocator.free(mem);

    try std.testing.expectEqualSlices(
        u8,
        "\x2B" ++ "\x06\x03\x00abc" ++ "\x07\x00\x00\x00\x00\x00\x00\x00\x00" ++ "\x1B\x11\x22\x33\x44" ++ "\x22\xEF\xBE",
        mem,
    );
}
