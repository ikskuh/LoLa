const std = @import("std");
const testing = std.testing;
const null_allocator = @import("null_allocator.zig").allocator;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

const TypeId = @TagType(Value);
const Value = union(enum) {
    const Self = @This();

    // non-allocating
    void: void,
    number: f64,
    object: u64,
    boolean: bool,

    // allocating
    string: String,
    array: Array,
    enumerator: Enumerator,

    fn initVoid() Self {
        return Self{ .void = {} };
    }

    fn initNumber(val: f64) Self {
        return Self{ .number = val };
    }

    fn initObject(id: u64) Self {
        return Self{ .object = id };
    }

    fn initBoolean(val: bool) Self {
        return Self{ .boolean = val };
    }

    /// Initializes a new value with string contents.
    fn initString(allocator: *std.mem.Allocator, text: []const u8) !Self {
        return Self{ .string = try String.init(allocator, text) };
    }

    /// Creates a new value that takes ownership of the passed string.
    /// This string must not be deinited.
    fn fromString(str: String) Self {
        return Self{ .string = str };
    }

    /// Creates a new value that takes ownership of the passed array.
    /// This array must not be deinited.
    fn fromArray(array: Array) Self {
        return Self{ .array = array };
    }

    /// Creates a new value with an enumerator. The array will be cloned
    /// into the enumerator and will not be owned.
    fn initEnumerator(array: Array) !Self {
        return Self{ .enumerator = try Enumerator.init(array) };
    }

    /// Creates a new value that takes ownership of the passed enumerator.
    /// This enumerator must not be deinited.
    fn fromEnumerator(enumerator: Enumerator) Self {
        return Self{ .enumerator = enumerator };
    }

    /// Duplicate this value.
    fn clone(self: Self) !Self {
        return switch (self) {
            .string => |s| try s.clone(),
            .array => |s| try s.clone(),
            .enumerator => |s| try s.clone(),
            .void, .number, .object, .boolean => self,
        };
    }

    /// Exchanges two values
    fn exchangeWith(self: *Self, other: *Self) void {
        const temp = self.*;
        self.* = other.*;
        other.* = temp;
    }

    /// Replaces the current instance with another instance.
    /// This will move the memory from the other instance into the
    /// current one. Calling deinit() on `other` after this function
    /// is an error.
    fn replaceWith(self: *Self, other: Self) void {
        self.deinit();
        self.* = other;
    }

    fn deinit(self: Self) void {
        switch (self) {
            .array => |a| a.deinit(),
            .string => |s| s.deinit(),
            .enumerator => |e| e.deinit(),
            else => {},
        }
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
    var value = Value{ .object = 2394 };
    defer value.deinit();
    std.debug.assert(value == .object);
    std.debug.assert(value.object == 2394);
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

const String = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    contents: []u8,

    fn init(allocator: *std.mem.Allocator, text: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .contents = try std.mem.dupe(allocator, u8, text),
        };
    }

    fn clone(self: Self) !Self {
        return Self{
            .allocator = self.allocator,
            .contents = try std.mem.dupe(self.allocator, u8, self.contents),
        };
    }

    fn deinit(self: Self) void {
        self.allocator.free(self.contents);
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

const Array = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    contents: []Value,

    fn init(allocator: *std.mem.Allocator, size: usize) !Self {
        var arr = Self{
            .allocator = allocator,
            .contents = try allocator.alloc(Value, size),
        };
        for (arr.contents) |*item| {
            item.* = Value{ .void = {} };
        }
        return arr;
    }

    fn clone(self: Self) !void {
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

    fn deinit(self: Self) void {
        for (self.contents) |item| {
            item.deinit();
        }
        self.allocator.free(self.contents);
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

const Enumerator = struct {
    const Self = @This();

    array: Array,
    index: usize,

    fn init(array: Array) !Self {
        return Enumerator{
            .array = try array.clone(),
            .index = 0,
        };
    }

    /// Checks if the enumerator has a next item.
    fn hasNext(self: Self) bool {
        return self.index < self.array.len;
    }

    /// Returns either a new, owned value or nothing.
    fn next(self: *Self) ?Value {
        if (self.index >= self.array.len)
            return null;
        const val = array[self.index];
        self.index += 1;
        return val.clone();
    }

    fn clone(self: Self) !void {
        return Self{
            .array = try self.array.clone(),
            .index = self.index,
        };
    }

    fn deinit(self: Self) void {
        self.array.deinit();
    }
};
