const std = @import("std");

pub const TypeId = @TagType(Value);
pub const Value = union(enum) {
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

    pub fn initVoid() Self {
        return Self{ .void = {} };
    }

    pub fn initNumber(val: f64) Self {
        return Self{ .number = val };
    }

    pub fn initObject(id: u64) Self {
        return Self{ .object = id };
    }

    pub fn initBoolean(val: bool) Self {
        return Self{ .boolean = val };
    }

    /// Initializes a new value with string contents.
    pub fn initString(allocator: *std.mem.Allocator, text: []const u8) !Self {
        return Self{ .string = try String.init(allocator, text) };
    }

    /// Initializes a new string literal.
    pub fn initStringLiteral(comptime text: []const u8) Self {
        return Self{ .string = String.initLiteral(text) };
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

    pub fn deinit(self: Self) void {
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

/// Immutable string type.
/// Both
const String = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    contents: []const u8,

    /// Clones `text` with the given parameter and stores the
    /// duplicated value.
    pub fn init(allocator: *std.mem.Allocator, text: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .contents = try std.mem.dupe(allocator, u8, text),
        };
    }

    /// Returns a string that will take ownership of the passed `text` and
    /// will free that with `allocator`.
    pub fn initFromOwned(allocator: *std.mem.Allocator, text: []const u8) Self {
        return Self{
            .allocator = allocator,
            .contents = text,
        };
    }

    /// Creates a string value that will not be freed as the passed `text`
    /// is located in static memory, not in the heap.
    pub fn initLiteral(comptime text: []const u8) Self {
        return initFromOwned(null_allocator, text);
    }

    pub fn clone(self: Self) error{OutOfMemory}!Self {
        return Self{
            .allocator = self.allocator,
            .contents = try std.mem.dupe(self.allocator, u8, self.contents),
        };
    }

    pub fn deinit(self: Self) void {
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

    pub fn init(allocator: *std.mem.Allocator, size: usize) !Self {
        var arr = Self{
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

    pub fn deinit(self: Self) void {
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

    /// Returns either a non-owned value or nothing.
    /// Do not deinit the returned value!
    /// The returned value is only valid as long as the
    /// enumerator is valid.
    pub fn next(self: *Self) ?Value {
        if (self.index >= self.array.contents.len)
            return null;
        const val = self.array.contents[self.index];
        self.index += 1;
        return val;
    }

    pub fn clone(self: Self) !Self {
        return Self{
            .array = try self.array.clone(),
            .index = self.index,
        };
    }

    pub fn deinit(self: Self) void {
        self.array.deinit();
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
    var b = enumerator.next() orelse return error.NotEnoughItems;
    var c = enumerator.next() orelse return error.NotEnoughItems;

    std.debug.assert(enumerator.next() == null);

    std.debug.assert(a == .string);
    std.debug.assert(b == .string);
    std.debug.assert(c == .string);

    std.debug.assert(std.mem.eql(u8, a.string.contents, "a"));
    std.debug.assert(std.mem.eql(u8, b.string.contents, "b"));
    std.debug.assert(std.mem.eql(u8, c.string.contents, "c"));
}
