const std = @import("std");

const objects = @import("objects.zig");
const Environment = @import("Environment.zig");

pub const TypeId = enum(u8) {
    void = 0,
    number = 1,
    object = 2,
    boolean = 3,
    string = 4,
    array = 5,
    enumerator = 6,
};

/// A struct that represents any possible LoLa value.
pub const Value = union(TypeId) {
    const Self = @This();

    // non-allocating
    void: void,
    number: f64,
    object: objects.ObjectHandle,
    boolean: bool,

    // allocating
    string: String,
    array: Array,
    enumerator: Enumerator,

    pub fn initNumber(val: f64) Self {
        return Self{ .number = val };
    }

    pub fn initInteger(comptime T: type, val: T) Self {
        comptime std.debug.assert(@typeInfo(T) == .int);
        return Self{ .number = @as(f64, @floatFromInt(val)) };
    }

    pub fn initObject(id: objects.ObjectHandle) Self {
        return Self{ .object = id };
    }

    pub fn initBoolean(val: bool) Self {
        return Self{ .boolean = val };
    }

    /// Initializes a new value with string contents.
    pub fn initString(allocator: std.mem.Allocator, text: []const u8) !Self {
        return Self{ .string = try String.init(allocator, text) };
    }

    /// Creates a new value that takes ownership of the passed string.
    /// This string must not be deinited.
    pub fn fromString(str: String) Self {
        return Self{ .string = str };
    }

    /// Creates a new value that takes ownership of the passed array.
    /// This array must not be deinited.
    pub fn fromArray(array: Array) Self {
        return Self{ .array = array };
    }

    /// Creates a new value with an enumerator. The array will be cloned
    /// into the enumerator and will not be owned.
    pub fn initEnumerator(array: Array) !Self {
        return Self{ .enumerator = try Enumerator.init(array) };
    }

    /// Creates a new value that takes ownership of the passed enumerator.
    /// This enumerator must not be deinited.
    pub fn fromEnumerator(enumerator: Enumerator) Self {
        return Self{ .enumerator = enumerator };
    }

    /// Duplicate this value.
    pub fn clone(self: Self) !Self {
        return switch (self) {
            .string => |s| Self{ .string = try s.clone() },
            .array => |a| Self{ .array = try a.clone() },
            .enumerator => |e| Self{ .enumerator = try e.clone() },
            .void, .number, .object, .boolean => self,
        };
    }

    /// Exchanges two values
    pub fn exchangeWith(self: *Self, other: *Self) void {
        const temp = self.*;
        self.* = other.*;
        other.* = temp;
    }

    /// Replaces the current instance with another instance.
    /// This will move the memory from the other instance into the
    /// current one. Calling deinit() on `other` after this function
    /// is an error.
    pub fn replaceWith(self: *Self, other: Self) void {
        self.deinit();
        self.* = other;
    }

    /// Checks if two values are equal.
    pub fn eql(lhs: Self, rhs: Self) bool {
        const Tag = std.meta.Tag(Self);
        if (@as(Tag, lhs) != @as(Tag, rhs))
            return false;
        return switch (lhs) {
            .void => true,
            .number => |n| n == rhs.number,
            .object => |o| o == rhs.object,
            .boolean => |b| b == rhs.boolean,
            .string => |s| String.eql(s, rhs.string),
            .array => |a| Array.eql(a, rhs.array),
            .enumerator => |e| Enumerator.eql(e, rhs.enumerator),
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .array => |*a| a.deinit(),
            .string => |*s| s.deinit(),
            .enumerator => |*e| e.deinit(),
            else => {},
        }
        self.* = undefined;
    }

    const ConversionError = error{ TypeMismatch, OutOfRange };

    pub fn toNumber(self: Self) ConversionError!f64 {
        if (self != .number)
            return error.TypeMismatch;
        return self.number;
    }

    pub fn toInteger(self: Self, comptime T: type) ConversionError!T {
        const num = @floor(try self.toNumber());
        if (num < std.math.minInt(T))
            return error.OutOfRange;
        //fix for error `'f64' cannot represent integer value '...'`
        const max: f64 = @floatFromInt(std.math.maxInt(T));
        if (std.math.floatMax(f64) > max and num > max)
            return error.OutOfRange;
        return @as(T, @intFromFloat(num));
    }

    pub fn toBoolean(self: Self) ConversionError!bool {
        if (self != .boolean)
            return error.TypeMismatch;
        return self.boolean;
    }

    pub fn toVoid(self: Self) ConversionError!void {
        if (self != .void)
            return error.TypeMismatch;
    }

    pub fn toObject(self: Self) ConversionError!objects.ObjectHandle {
        if (self != .object)
            return error.TypeMismatch;
        return self.object;
    }

    pub fn toArray(self: Self) ConversionError!Array {
        if (self != .array)
            return error.TypeMismatch;
        return self.array;
    }

    /// Returns either the string contents or errors with TypeMismatch
    pub fn toString(self: Self) ConversionError![]const u8 {
        if (self != .string)
            return error.TypeMismatch;
        return self.string.contents;
    }

    /// Gets the contained array or fails.
    pub fn getArray(self: *Self) ConversionError!*Array {
        if (self.* != .array)
            return error.TypeMismatch;
        return &self.array;
    }

    /// Gets the contained enumerator or fails.
    pub fn getEnumerator(self: *Self) ConversionError!*Enumerator {
        if (self.* != .enumerator)
            return error.TypeMismatch;
        return &self.enumerator;
    }

    fn formatArray(a: Array, stream: anytype) !void {
        try stream.writeAll("[");
        for (a.contents, 0..) |item, i| {
            if (i > 0)
                try stream.writeAll(",");

            // Workaround until #???? is fixed:
            // Print only the type name of the array item.
            // const itemType = @as(TypeId, item);
            // try std.fmt.format(context, Errors, output, " {}", .{@tagName(itemType)});
            try stream.print(" {f}", .{item});
        }
        try stream.writeAll(" ]");
    }

    /// Prints a LoLa value to the given stream.
    pub fn format(value: Self, stream: *std.Io.Writer) std.Io.Writer.Error!void {
        return switch (value) {
            .void => stream.writeAll("void"),
            .number => |n| stream.print("{d}", .{n}),
            .object => |o| stream.print("${d}", .{o}),
            .boolean => |b| if (b) stream.writeAll("true") else stream.writeAll("false"),
            .string => |s| stream.print("\"{s}\"", .{s.contents}),
            .array => |a| formatArray(a, stream),
            .enumerator => |e| stream.print("enumerator({}/{})", .{ e.index, e.array.contents.len }),
        };
    }

    /// Serializes the value into the given `writer`.
    /// Note that this does not serialize object values but only references. It is required to serialize the corresponding
    /// object pool as well to gain restorability of objects.
    pub fn serialize(self: Self, writer: *std.Io.Writer) (@TypeOf(writer.*).Error || error{ NotSupported, ObjectTooLarge })!void {
        try writer.writeByte(@intFromEnum(@as(TypeId, self)));
        switch (self) {
            .void => return, // void values are empty \o/
            .number => |val| try writer.writeAll(std.mem.asBytes(&val)),
            .object => |val| try writer.writeInt(u64, @intFromEnum(val), .little),
            .boolean => |val| try writer.writeByte(if (val) @as(u8, 1) else 0),
            .string => |val| {
                try writer.writeInt(u32, std.math.cast(u32, val.contents.len) orelse return error.ObjectTooLarge, .little);
                try writer.writeAll(val.contents);
            },
            .array => |arr| {
                try writer.writeInt(u32, std.math.cast(u32, arr.contents.len) orelse return error.ObjectTooLarge, .little);
                for (arr.contents) |item| {
                    try item.serialize(writer);
                }
            },
            .enumerator => |e| {
                try writer.writeInt(u32, std.math.cast(u32, e.array.contents.len) orelse return error.ObjectTooLarge, .little);
                try writer.writeInt(u32, std.math.cast(u32, e.index) orelse return error.ObjectTooLarge, .little);
                for (e.array.contents) |item| {
                    try item.serialize(writer);
                }
            },
        }
    }

    /// Deserializes a value from the `reader`, using `allocator` to allocate memory.
    /// Note that if objects are deserialized you need to also deserialize the corresponding object pool
    pub fn deserialize(reader: *std.Io.Reader, allocator: std.mem.Allocator) (@TypeOf(reader.*).Error || error{ OutOfMemory, InvalidEnumTag, EndOfStream, NotSupported })!Self {
        const type_id_src = try reader.takeByte();
        const type_id = try std.meta.intToEnum(TypeId, type_id_src);
        return switch (type_id) {
            .void => .void,
            .number => blk: {
                var buffer: [@sizeOf(f64)]u8 align(@alignOf(f64)) = undefined;

                try reader.readSliceAll(&buffer);

                break :blk initNumber(@as(f64, @bitCast(buffer)));
            },
            .object => initObject(@as(objects.ObjectHandle, @enumFromInt(try reader.takeInt(std.meta.Tag(objects.ObjectHandle), .little)))),
            .boolean => initBoolean((try reader.takeByte()) != 0),
            .string => blk: {
                const size = try reader.takeInt(u32, .little);

                const buffer = try allocator.alloc(u8, size);
                errdefer allocator.free(buffer);

                try reader.readSliceAll(buffer);

                break :blk fromString(String.initFromOwned(allocator, buffer));
            },
            .array => blk: {
                const size = try reader.takeInt(u32, .little);
                var array = try Array.init(allocator, size);
                errdefer array.deinit();

                for (array.contents) |*item| {
                    item.* = try deserialize(reader, allocator);
                }

                break :blk fromArray(array);
            },
            .enumerator => blk: {
                const size = try reader.takeInt(u32, .little);
                const index = try reader.takeInt(u32, .little);

                var array = try Array.init(allocator, size);
                errdefer array.deinit();

                for (array.contents) |*item| {
                    item.* = try deserialize(reader, allocator);
                }

                break :blk fromEnumerator(Enumerator{
                    .array = array,
                    .index = index,
                });
            },
        };
    }
};

test "Value.void" {
    var voidVal = Value{ .void = {} };
    defer voidVal.deinit();

    std.debug.assert(voidVal == .void);
}

test "Value.number" {
    var value = Value{ .number = 3.14 };
    defer value.deinit();
    std.debug.assert(value == .number);
    std.debug.assert(value.number == 3.14);
}

test "Value.boolean" {
    var value = Value{ .boolean = true };
    defer value.deinit();
    std.debug.assert(value == .boolean);
    std.debug.assert(value.boolean == true);
}

test "Value.object" {
    var value = Value{ .object = @as(objects.ObjectHandle, @enumFromInt(2394)) };
    defer value.deinit();
    std.debug.assert(value == .object);
    std.debug.assert(value.object == @as(objects.ObjectHandle, @enumFromInt(2394)));
}

test "Value.string (move)" {
    var value = Value.fromString(try String.init(std.testing.allocator, "Hello"));
    defer value.deinit();

    std.debug.assert(value == .string);
    std.debug.assert(std.mem.eql(u8, value.string.contents, "Hello"));
}

test "Value.string (init)" {
    var value = try Value.initString(std.testing.allocator, "Malloc'd");
    defer value.deinit();

    std.debug.assert(value == .string);
    std.debug.assert(std.mem.eql(u8, value.string.contents, "Malloc'd"));
}

test "Value.eql (void)" {
    const v1: Value = .void;
    const v2: Value = .void;

    std.debug.assert(v1.eql(v2));
}

test "Value.eql (boolean)" {
    const v1 = Value.initBoolean(true);
    const v2 = Value.initBoolean(true);
    const v3 = Value.initBoolean(false);

    std.debug.assert(v1.eql(v2));
    std.debug.assert(v2.eql(v1));
    std.debug.assert(v1.eql(v3) == false);
    std.debug.assert(v2.eql(v3) == false);
}

test "Value.eql (number)" {
    const v1 = Value.initNumber(1.3);
    const v2 = Value.initNumber(1.3);
    const v3 = Value.initNumber(2.3);

    std.debug.assert(v1.eql(v2));
    std.debug.assert(v2.eql(v1));
    std.debug.assert(v1.eql(v3) == false);
    std.debug.assert(v2.eql(v3) == false);
}

test "Value.eql (object)" {
    const v1 = Value.initObject(@as(objects.ObjectHandle, @enumFromInt(1)));
    const v2 = Value.initObject(@as(objects.ObjectHandle, @enumFromInt(1)));
    const v3 = Value.initObject(@as(objects.ObjectHandle, @enumFromInt(2)));

    std.debug.assert(v1.eql(v2));
    std.debug.assert(v2.eql(v1));
    std.debug.assert(v1.eql(v3) == false);
    std.debug.assert(v2.eql(v3) == false);
}

test "Value.eql (string)" {
    var v1 = try Value.initString(std.testing.allocator, "a");
    defer v1.deinit();

    var v2 = try Value.initString(std.testing.allocator, "a");
    defer v2.deinit();

    var v3 = try Value.initString(std.testing.allocator, "b");
    defer v3.deinit();

    std.debug.assert(v1.eql(v2));
    std.debug.assert(v2.eql(v1));
    std.debug.assert(v1.eql(v3) == false);
    std.debug.assert(v2.eql(v3) == false);
}

/// Immutable string type.
/// Both
pub const String = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    contents: []const u8,
    refcount: ?*usize,

    /// Creates a new, uninitialized string
    pub fn initUninitialized(allocator: std.mem.Allocator, length: usize) !Self {
        const alignment = std.mem.Alignment.of(usize);

        const ptr_offset = alignment.forward(length);
        const buffer = try allocator.alignedAlloc(
            u8,
            alignment,
            ptr_offset + @sizeOf(usize),
        );
        std.mem.writeInt(usize, buffer[ptr_offset..][0..@sizeOf(usize)], 1, .little);

        return Self{
            .allocator = allocator,
            .contents = buffer[0..length],
            .refcount = @ptrCast(@alignCast(buffer.ptr + ptr_offset)),
        };
    }

    /// Clones `text` with the given parameter and stores the
    /// duplicated value.
    pub fn init(allocator: std.mem.Allocator, text: []const u8) !Self {
        var string = try initUninitialized(allocator, text.len);
        @memcpy(
            string.obtainMutableStorage() catch unreachable,
            text,
        );
        return string;
    }

    /// Returns a string that will take ownership of the passed `text` and
    /// will free that with `allocator`.
    pub fn initFromOwned(allocator: std.mem.Allocator, text: []const u8) Self {
        return Self{
            .allocator = allocator,
            .contents = text,
            .refcount = null,
        };
    }

    /// Returns a muable slice of the string elements.
    /// This may fail with `error.Forbidden` when the string is referenced more than once.
    pub fn obtainMutableStorage(self: *Self) error{Forbidden}![]u8 {
        if (self.refcount) |rc| {
            std.debug.assert(rc.* > 0);
            if (rc.* > 1)
                return error.Forbidden;
        }
        // this is safe as we allocated the memory, so it is actually mutable
        return @as([*]u8, @ptrFromInt(@intFromPtr(self.contents.ptr)))[0..self.contents.len];
    }

    pub fn clone(self: Self) error{OutOfMemory}!Self {
        if (self.refcount) |rc| {
            // we can just increase reference count here
            rc.* += 1;
            return self;
        } else {
            // otherwise, return a new copy which is now reference-counted
            // -> performance opt-in
            return try init(self.allocator, self.contents);
        }
    }

    pub fn eql(lhs: Self, rhs: Self) bool {
        return std.mem.eql(u8, lhs.contents, rhs.contents);
    }

    pub fn deinit(self: *Self) void {
        if (self.refcount) |rc| {
            std.debug.assert(rc.* > 0);
            rc.* -= 1;

            if (rc.* > 0)
                return;

            // patch-up the old length so the allocator will know what happened
            self.contents.len = std.mem.alignForward(usize, self.contents.len, @alignOf(usize)) + @sizeOf(usize);
            self.allocator.free(@as([]align(@alignOf(usize)) const u8, @alignCast(self.contents)));
        } else {
            self.allocator.free(self.contents);
        }

        self.* = undefined;
    }
};

test "String" {
    var text = try String.init(std.testing.allocator, "Hello, World!");
    std.debug.assert(std.mem.eql(u8, text.contents, "Hello, World!"));

    var text2 = try text.clone();

    text.deinit();

    std.debug.assert(std.mem.eql(u8, text2.contents, "Hello, World!"));
    text2.deinit();
}

test "String.eql" {
    var str1 = try String.init(std.testing.allocator, "Hello, World!");
    defer str1.deinit();

    var str2 = try String.init(std.testing.allocator, "Hello, World!");
    defer str2.deinit();

    var str3 = try String.init(std.testing.allocator, "World, Hello!");
    defer str3.deinit();

    std.debug.assert(str1.eql(str2));
    std.debug.assert(str2.eql(str1));
    std.debug.assert(str1.eql(str3) == false);
    std.debug.assert(str2.eql(str3) == false);
}

pub const Array = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    contents: []Value,

    pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
        const arr = Self{
            .allocator = allocator,
            .contents = try allocator.alloc(Value, size),
        };
        for (arr.contents) |*item| {
            item.* = Value{ .void = {} };
        }
        return arr;
    }

    pub fn clone(self: Self) error{OutOfMemory}!Self {
        var arr = Self{
            .allocator = self.allocator,
            .contents = try self.allocator.alloc(Value, self.contents.len),
        };
        errdefer arr.allocator.free(arr.contents);

        var index: usize = 0;

        // Cleanup all successfully cloned items
        errdefer {
            var i: usize = 0;
            while (i < index) : (i += 1) {
                arr.contents[i].deinit();
            }
        }

        while (index < arr.contents.len) : (index += 1) {
            arr.contents[index] = try self.contents[index].clone();
        }
        return arr;
    }

    pub fn eql(lhs: Self, rhs: Self) bool {
        if (lhs.contents.len != rhs.contents.len)
            return false;
        for (lhs.contents, 0..) |v, i| {
            if (!Value.eql(v, rhs.contents[i]))
                return false;
        }
        return true;
    }

    pub fn deinit(self: *Self) void {
        for (self.contents) |*item| {
            item.deinit();
        }
        self.allocator.free(self.contents);
        self.* = undefined;
    }
};

test "Array" {
    var array = try Array.init(std.testing.allocator, 3);
    defer array.deinit();

    std.debug.assert(array.contents.len == 3);
    std.debug.assert(array.contents[0] == .void);
    std.debug.assert(array.contents[1] == .void);
    std.debug.assert(array.contents[2] == .void);

    array.contents[0].replaceWith(Value.initBoolean(true));
    array.contents[1].replaceWith(try Value.initString(std.testing.allocator, "Hello"));
    array.contents[2].replaceWith(Value.initNumber(45.0));

    std.debug.assert(array.contents[0] == .boolean);
    std.debug.assert(array.contents[1] == .string);
    std.debug.assert(array.contents[2] == .number);
}

test "Array.eql" {
    var array1 = try Array.init(std.testing.allocator, 2);
    defer array1.deinit();

    array1.contents[0] = Value.initBoolean(true);
    array1.contents[1] = Value.initNumber(42);

    var array2 = try Array.init(std.testing.allocator, 2);
    defer array2.deinit();

    array2.contents[0] = Value.initBoolean(true);
    array2.contents[1] = Value.initNumber(42);

    var array3 = try Array.init(std.testing.allocator, 2);
    defer array3.deinit();

    array3.contents[0] = Value.initBoolean(true);
    array3.contents[1] = Value.initNumber(43);

    var array4 = try Array.init(std.testing.allocator, 3);
    defer array4.deinit();

    std.debug.assert(array1.eql(array2));
    std.debug.assert(array2.eql(array1));

    std.debug.assert(array1.eql(array3) == false);
    std.debug.assert(array2.eql(array3) == false);

    std.debug.assert(array1.eql(array4) == false);
    std.debug.assert(array2.eql(array4) == false);
    std.debug.assert(array3.eql(array4) == false);
}

pub const Enumerator = struct {
    const Self = @This();

    array: Array,
    index: usize,

    /// Creates a new enumerator that will clone the contained value.
    pub fn init(array: Array) !Self {
        return Self{
            .array = try array.clone(),
            .index = 0,
        };
    }

    /// Creates a new enumerator that will own the passed value.
    pub fn initFromOwned(array: Array) Self {
        return Self{
            .array = array,
            .index = 0,
        };
    }

    /// Checks if the enumerator has a next item.
    pub fn hasNext(self: Self) bool {
        return self.index < self.array.contents.len;
    }

    /// Returns either a owned value or nothing.
    /// Will replace the returned value in the enumerator array with `void`.
    /// As the enumerator can only yield values from the array and does not "store"
    /// them for later use, this prevents unnecessary clones.
    pub fn next(self: *Self) ?Value {
        if (self.index >= self.array.contents.len)
            return null;
        var result: Value = .void;
        self.array.contents[self.index].exchangeWith(&result);
        self.index += 1;
        return result;
    }

    pub fn clone(self: Self) !Self {
        return Self{
            .array = try self.array.clone(),
            .index = self.index,
        };
    }

    // Enumerators are never equal to each other.
    pub fn eql(lhs: Self, rhs: Self) bool {
        _ = lhs;
        _ = rhs;
        return false;
    }

    pub fn deinit(self: *Self) void {
        self.array.deinit();
        self.* = undefined;
    }
};

test "Enumerator" {
    var array = try Array.init(std.testing.allocator, 3);
    array.contents[0] = try Value.initString(std.testing.allocator, "a");
    array.contents[1] = try Value.initString(std.testing.allocator, "b");
    array.contents[2] = try Value.initString(std.testing.allocator, "c");

    var enumerator = Enumerator.initFromOwned(array);
    defer enumerator.deinit();

    std.debug.assert(enumerator.hasNext());

    var a = enumerator.next() orelse return error.NotEnoughItems;
    defer a.deinit();

    var b = enumerator.next() orelse return error.NotEnoughItems;
    defer b.deinit();

    var c = enumerator.next() orelse return error.NotEnoughItems;
    defer c.deinit();

    std.debug.assert(enumerator.next() == null);

    std.debug.assert(a == .string);
    std.debug.assert(b == .string);
    std.debug.assert(c == .string);

    std.debug.assert(std.mem.eql(u8, a.string.contents, "a"));
    std.debug.assert(std.mem.eql(u8, b.string.contents, "b"));
    std.debug.assert(std.mem.eql(u8, c.string.contents, "c"));
}

test "Enumerator.eql" {
    var array = try Array.init(std.testing.allocator, 0);
    defer array.deinit();

    var enumerator1 = try Enumerator.init(array);
    defer enumerator1.deinit();

    var enumerator2 = try Enumerator.init(array);
    defer enumerator2.deinit();

    std.debug.assert(enumerator1.eql(enumerator2) == false);
}
