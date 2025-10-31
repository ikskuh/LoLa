const std = @import("std");
const builtin = @import("builtin");
const interfaces = @import("../common/interface.zig");

const Environment = @import("Environment.zig");

const vm_unit = @import("vm.zig");
const Value = @import("value.zig").Value;

/// Non-owning interface to a abstract LoLa object.
/// It is associated with a object handle in the `ObjectPool` and provides
/// a way to get methods as well as destroy the object when it's garbage collected.
pub const Object = struct {
    const Interface = interfaces.Interfaces(.{
        .getMethod = fn (self: *interfaces.Self, name: []const u8) ?Environment.Function,
        .destroyObject = fn (self: *interfaces.Self) void,
    });

    const ClassVTable = interfaces.Interfaces(.{
        .serializeObject = fn (self: *interfaces.Self, stream: OutputStream) anyerror!void,
        .deserializeObject = fn (stream: InputStream) anyerror!*interfaces.Self,
    });

    const Self = @This();

    ptr: *anyopaque,
    vtable: *const Interface.VTable,

    pub fn init(ptr: anytype) Self {
        return Self{
            .ptr = ptr,
            .vtable = Interface.createVTable(@TypeOf(ptr.*)),
        };
    }

    pub fn getMethod(self: *const Self, name: []const u8) ?Environment.Function {
        return self.vtable.getMethod(self.ptr, name);
    }

    pub fn destroyObject(self: *Self) void {
        self.vtable.destroyObject(self.ptr);
        self.* = undefined;
    }
};

/// A opaque handle to objects. These are used inside the virtual machine and environment and
/// will be passed around. They do not hold any memory references and require an object pool to
/// resolve to actual objects.
pub const ObjectHandle = enum(u64) {
    const Self = @This();

    _, // Just an non-exhaustive handle, no named members
};

pub const InputStream = struct {
    const Self = @This();
    pub const Reader = *std.Io.Reader;

    interface: *std.Io.Reader,

    fn from(reader_ptr: *std.Io.Reader) Self {
        return Self{
            .interface = reader_ptr,
        };
    }

    fn reader(self: *@This()) Reader {
        return self.interface;
    }
};

pub const OutputStream = struct {
    const Self = @This();
    pub const Writer = *std.Io.Writer;

    interface: *std.Io.Writer,

    fn from(writer_ptr: *std.Io.Writer) Self {
        return Self{
            .interface = writer_ptr,
        };
    }

    fn writer(self: *@This()) Writer {
        return self.interface;
    }
};

const ObjectGetError = error{InvalidObject};

pub const ObjectPoolInterface = struct {
    const ErasedSelf = opaque {};

    self: *ErasedSelf,

    getMethodFn: *const (fn (self: *ErasedSelf, handle: ObjectHandle, name: []const u8) ObjectGetError!?Environment.Function),
    destroyObjectFn: *const (fn (self: *ErasedSelf, handle: ObjectHandle) void),
    isObjectValidFn: *const (fn (self: *ErasedSelf, handle: ObjectHandle) bool),

    pub fn getMethod(self: @This(), handle: ObjectHandle, name: []const u8) ObjectGetError!?Environment.Function {
        return self.getMethodFn(self.self, handle, name);
    }

    pub fn destroyObject(self: @This(), handle: ObjectHandle) void {
        return self.destroyObjectFn(self.self, handle);
    }

    pub fn isObjectValid(self: @This(), handle: ObjectHandle) bool {
        return self.isObjectValidFn(self.self, handle);
    }

    pub fn castTo(self: *@This(), comptime PoolType: type) *PoolType {
        return @as(*PoolType, @ptrCast(@alignCast(self.self)));
    }
};

const TypeListInfo = struct {
    all_can_serialize: bool,
    hash: u64,
};

fn computeTypeListHash(comptime classes: []const type) TypeListInfo {
    var hasher = std.hash.SipHash64(2, 4).init("OP SER Version 1");
    var all_classes_can_serialize = (classes.len > 0);
    inline for (classes) |class| {
        const can_serialize = @hasDecl(class, "serializeObject");
        if (can_serialize != @hasDecl(class, "deserializeObject")) {
            @compileError("Each class requires either both serializeObject and deserializeObject to be present or none.");
        }

        all_classes_can_serialize = all_classes_can_serialize and can_serialize;

        // this requires to use a typeHash structure instead of the type name
        hasher.update(@typeName(class));
    }
    return TypeListInfo{
        .hash = hasher.finalInt(),
        .all_can_serialize = all_classes_can_serialize,
    };
}

/// An object pool is a structure that is used for garbage collecting objects.
/// Each object gets a unique number assigned when being put into the pool
/// via `createObject`. This handle can then be passed into a VM, used opaquely.
/// The VM can also request methods from objects via `getMethod` call.
/// To collect garbage, the following procedure should be done:
/// 1. Call `clearUsageCounters` to initiate garbage collection
/// 2. Call `walkEnvironment`, `walkVM` or `walkValue` to collect all live objects in different elements
/// 3. Call `collectGarbage` to delete all objects that have no reference counters set.
/// For each object to be deleted, `destroyObject` is invoked and the object is removed from the pool.
/// To retain objects by hand in areas not reachable by any of the `walk*` functions, it's possible to
/// call `retainObject` to increment the reference counter by 1 and `releaseObject` to reduce it by one.
/// Objects marked with this reference counter will not be deleted even when the object is not encountered
/// betewen `clearUsageCounters` and `collectGarbage`.
pub fn ObjectPool(comptime classes_list: anytype) type {
    // enforce type safety here
    const classes: [@typeInfo(@TypeOf(classes_list)).array.len]type = classes_list;

    const list_info = comptime computeTypeListHash(&classes);

    const all_classes_can_serialize = list_info.all_can_serialize;
    const pool_signature = list_info.hash;

    const TypeIndex = std.meta.Int(
        .unsigned,
        // We need 1 extra value, so 0xFFFF… is never a valid type index
        // this marks the end of objects in the stream
        std.mem.alignForward(usize, std.math.log2_int_ceil(usize, classes.len + 1), 8),
    );

    const ClassInfo = struct {
        name: []const u8,
        serialize: *const fn (stream: OutputStream, obj: Object) anyerror!void,
        deserialize: *const fn (allocator: std.mem.Allocator, stream: InputStream) anyerror!Object,
    };

    // Provide a huge-enough branch quota
    @setEvalBranchQuota(1000 * (classes.len + 1));

    const class_lut = comptime if (all_classes_can_serialize) blk: {
        var lut: [classes.len]ClassInfo = undefined;
        for (&lut, 0..) |*info, i| {
            const Class = classes[i];

            const Interface = struct {
                fn serialize(stream: OutputStream, obj: Object) anyerror!void {
                    //parameters are immutable so save to mutable var
                    var s = stream;
                    try Class.serializeObject(s.writer(), @as(*Class, @ptrCast(@alignCast(obj.ptr))));
                }

                fn deserialize(allocator: std.mem.Allocator, stream: InputStream) anyerror!Object {
                    var s = stream;
                    const ptr = try Class.deserializeObject(allocator, s.reader());
                    return Object.init(ptr);
                }
            };

            info.* = ClassInfo{
                .name = @typeName(Class),
                .serialize = Interface.serialize,
                .deserialize = Interface.deserialize,
            };
        }
        break :blk lut;
    } else {};

    return struct {
        const Self = @This();

        const ManagedObject = struct {
            refcount: usize,
            manualRefcount: usize,
            object: Object,
            class_id: TypeIndex,
        };

        /// Is `true` when all classes in the ObjectPool allow seriaization
        pub const serializable: bool = all_classes_can_serialize;

        /// ever-increasing number which is used to allocate new object handles.
        objectCounter: u64,

        /// stores all alive objects. Removing elements from this
        /// requires to call `.object.destroyObject()`!
        objects: std.AutoHashMap(ObjectHandle, ManagedObject),

        /// Creates a new object pool, using `allocator` to handle hashmap allocations.
        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .objectCounter = 0,
                .objects = std.AutoHashMap(ObjectHandle, ManagedObject).init(allocator),
            };
        }

        /// Destroys all objects in the pool, then releases all associated memory.
        /// Do not use the ObjectPool afterwards!
        pub fn deinit(self: *Self) void {
            var iter = self.objects.iterator();
            while (iter.next()) |obj| {
                obj.value_ptr.object.destroyObject();
            }
            self.objects.deinit();
            self.* = undefined;
        }

        // Serialization API

        /// Serializes the whole object pool into the `stream`.
        pub fn serialize(self: Self, stream: *std.Io.Writer) !void {
            if (all_classes_can_serialize) {
                try stream.writeInt(u64, pool_signature, .little);

                var iter = self.objects.iterator();
                while (iter.next()) |entry| {
                    const obj = entry.value_ptr;
                    var class = class_lut[obj.class_id];

                    try stream.writeInt(TypeIndex, obj.class_id, .little);
                    try stream.writeInt(u64, @intFromEnum(entry.key_ptr.*), .little);

                    try class.serialize(OutputStream.from(stream), obj.object);
                }

                try stream.writeInt(TypeIndex, std.math.maxInt(TypeIndex), .little);
            } else {
                @compileError("This ObjectPool is not serializable!");
            }
        }

        /// Deserializes a object pool from `steam` and returns it.
        pub fn deserialize(allocator: std.mem.Allocator, stream: *std.Io.Reader) !Self {
            if (all_classes_can_serialize) {
                var pool = init(allocator);
                errdefer pool.deinit();

                const signature = try stream.takeInt(u64, .little);
                if (signature != pool_signature)
                    return error.InvalidStream;

                while (true) {
                    const type_index = try stream.takeInt(TypeIndex, .little);
                    if (type_index == std.math.maxInt(TypeIndex))
                        break; // end of objects
                    if (type_index >= class_lut.len)
                        return error.InvalidStream;
                    const object_id = try stream.takeInt(u64, .little);
                    pool.objectCounter = @max(object_id + 1, pool.objectCounter);

                    const gop = try pool.objects.getOrPut(@as(ObjectHandle, @enumFromInt(object_id)));
                    if (gop.found_existing)
                        return error.InvalidStream;

                    const object = try class_lut[type_index].deserialize(allocator, InputStream.from(stream));

                    gop.value_ptr.* = ManagedObject{
                        .object = object,
                        .refcount = 0,
                        .manualRefcount = 0,
                        .class_id = type_index,
                    };
                }

                return pool;
            } else {
                @compileError("This ObjectPool is not serializable!");
            }
        }

        // Public API

        /// Inserts a new object into the pool and returns a handle to it.
        /// `object_ptr` must be a mutable pointer to the object itself.
        pub fn createObject(self: *Self, object_ptr: anytype) !ObjectHandle {
            const ObjectTypeInfo = @typeInfo(@TypeOf(object_ptr)).pointer;
            if (ObjectTypeInfo.is_const)
                @compileError("Passing a const pointer to ObjectPool.createObject is not allowed!");

            // Calculate the index of the type:
            const type_index = inline for (classes, 0..) |class, index| {
                if (class == ObjectTypeInfo.child)
                    break index;
            } else @compileError("The type " ++ @typeName(ObjectTypeInfo.child) ++ " is not valid for this object pool. Add it to the class list in the type definition to allow creation.");

            const object = Object.init(object_ptr);

            self.objectCounter += 1;
            errdefer self.objectCounter -= 1;
            const handle = @as(ObjectHandle, @enumFromInt(self.objectCounter));
            try self.objects.putNoClobber(handle, ManagedObject{
                .object = object,
                .refcount = 0,
                .manualRefcount = 0,
                .class_id = type_index,
            });
            return handle;
        }

        /// Keeps the object from beeing garbage collected.
        /// To allow recollection, call `releaseObject`.
        pub fn retainObject(self: *Self, object: ObjectHandle) ObjectGetError!void {
            if (self.objects.getEntry(object)) |obj| {
                obj.value_ptr.manualRefcount += 1;
            } else {
                return error.InvalidObject;
            }
        }

        /// Removes a restrain from `retainObject` to re-allow garbage collection.
        pub fn releaseObject(self: *Self, object: ObjectHandle) ObjectGetError!void {
            if (self.objects.getEntry(object)) |obj| {
                obj.value_ptr.manualRefcount -= 1;
            } else {
                return error.InvalidObject;
            }
        }

        /// Destroys an object by external means. This will also invoke the object destructor.
        pub fn destroyObject(self: *Self, object: ObjectHandle) void {
            if (self.objects.fetchRemove(object)) |obj| {
                var copy = obj.value.object;
                copy.destroyObject();
            }
        }

        /// Returns if an object handle is still valid.
        pub fn isObjectValid(self: Self, object: ObjectHandle) bool {
            return (self.objects.get(object) != null);
        }

        /// Gets the method of an object or `null` if the method does not exist.
        /// The returned `Function` is non-owned.
        pub fn getMethod(self: Self, object: ObjectHandle, name: []const u8) ObjectGetError!?Environment.Function {
            if (self.objects.get(object)) |obj| {
                return obj.object.getMethod(name);
            } else {
                return error.InvalidObject;
            }
        }

        // Garbage Collector API

        /// Sets all usage counters to zero.
        pub fn clearUsageCounters(self: *Self) void {
            var iter = self.objects.iterator();
            while (iter.next()) |obj| {
                obj.value_ptr.refcount = 0;
            }
        }

        /// Marks an object handle as used
        pub fn markUsed(self: *Self, object: ObjectHandle) ObjectGetError!void {
            if (self.objects.getEntry(object)) |obj| {
                obj.value_ptr.refcount += 1;
            } else {
                return error.InvalidObject;
            }
        }

        /// Walks through the value marks all referenced objects as used.
        pub fn walkValue(self: *Self, value: Value) ObjectGetError!void {
            switch (value) {
                .object => |oid| try self.markUsed(oid),
                .array => |arr| for (arr.contents) |val| {
                    try self.walkValue(val);
                },
                else => {},
            }
        }

        /// Walks through all values stored in an environment and marks all referenced objects as used.
        pub fn walkEnvironment(self: *Self, env: Environment) ObjectGetError!void {
            for (env.scriptGlobals) |glob| {
                try self.walkValue(glob);
            }
        }

        /// Walks through all values stored in a virtual machine and marks all referenced objects as used.
        pub fn walkVM(self: *Self, vm: vm_unit.VM) ObjectGetError!void {
            for (vm.stack.items) |val| {
                try self.walkValue(val);
            }

            for (vm.calls.items) |call| {
                for (call.locals) |local| {
                    try self.walkValue(local);
                }
            }
        }

        /// Removes and destroys all objects that are not marked as used.
        pub fn collectGarbage(self: *Self) void {
            // Now this?!
            var iter = self.objects.iterator();
            while (iter.next()) |obj| {
                if (obj.value_ptr.refcount == 0 and obj.value_ptr.manualRefcount == 0) {
                    if (self.objects.fetchRemove(obj.key_ptr.*)) |kv| {
                        var temp_obj = kv.value.object;
                        temp_obj.destroyObject();
                    } else {
                        unreachable;
                    }

                    // Hack: Remove modification safety check,
                    // we want to mutate the HashMap!
                    // iter.initial_modification_count = iter.hm.modification_count;
                }
            }
        }

        // Interface API:

        /// Returns the non-generic interface for this object pool.
        /// Pass this to `Environment` or other LoLa components.
        pub fn interface(self: *Self) ObjectPoolInterface {
            const Impl = struct {
                const ErasedSelf = ObjectPoolInterface.ErasedSelf;

                fn cast(erased_self: *ErasedSelf) *Self {
                    return @as(*Self, @ptrCast(@alignCast(erased_self)));
                }
                fn getMethod(erased_self: *ErasedSelf, handle: ObjectHandle, name: []const u8) ObjectGetError!?Environment.Function {
                    return cast(erased_self).getMethod(handle, name);
                }
                fn destroyObject(erased_self: *ErasedSelf, handle: ObjectHandle) void {
                    return cast(erased_self).destroyObject(handle);
                }
                fn isObjectValid(erased_self: *ErasedSelf, handle: ObjectHandle) bool {
                    return cast(erased_self).isObjectValid(handle);
                }
            };

            return ObjectPoolInterface{
                .self = @as(*ObjectPoolInterface.ErasedSelf, @ptrCast(self)),
                .destroyObjectFn = Impl.destroyObject,
                .getMethodFn = Impl.getMethod,
                .isObjectValidFn = Impl.isObjectValid,
            };
        }
    };
}

const TestObject = struct {
    const Self = @This();

    got_method_query: bool = false,
    got_destroy_call: bool = false,
    was_serialized: bool = false,
    was_deserialized: bool = false,

    pub fn getMethod(self: *Self, name: []const u8) ?Environment.Function {
        self.got_method_query = true;
        _ = name;
        return null;
    }

    pub fn destroyObject(self: *Self) void {
        self.got_destroy_call = true;
    }

    pub fn serializeObject(writer: OutputStream.Writer, object: *Self) !void {
        try writer.writeAll("test object");
        object.was_serialized = true;
    }

    var deserialize_instance = Self{};

    pub fn deserializeObject(allocator: std.mem.Allocator, reader: InputStream.Reader) !*Self {
        _ = allocator;
        var buf: [11]u8 = undefined;
        try reader.readSliceAll(&buf);
        try std.testing.expectEqualStrings("test object", &buf);
        deserialize_instance.was_deserialized = true;
        return &deserialize_instance;
    }
};

const TestPool = ObjectPool([_]type{TestObject});

comptime {
    if (builtin.is_test) {
        {
            if (ObjectPool([_]type{}).serializable != false)
                @compileError("Empty ObjectPool is required to be unserializable!");
        }

        {
            if (TestPool.serializable != true)
                @compileError("TestPool is required to be serializable!");
        }

        {
            const Unserializable = struct {
                const Self = @This();
                pub fn getMethod(self: *Self, name: []const u8) ?Environment.Function {
                    _ = self;
                    _ = name;
                    unreachable;
                }

                pub fn destroyObject(self: *Self) void {
                    _ = self;

                    unreachable;
                }
            };

            if (ObjectPool([_]type{ TestObject, Unserializable }).serializable != false)
                @compileError("Unserializable detection doesn't work!");
        }
    }
}

test "Object" {
    var test_obj = TestObject{};
    var object = Object.init(&test_obj);

    try std.testing.expectEqual(false, test_obj.got_destroy_call);
    try std.testing.expectEqual(false, test_obj.got_method_query);

    _ = object.getMethod("irrelevant");

    try std.testing.expectEqual(false, test_obj.got_destroy_call);
    try std.testing.expectEqual(true, test_obj.got_method_query);

    object.destroyObject();

    try std.testing.expectEqual(true, test_obj.got_destroy_call);
    try std.testing.expectEqual(true, test_obj.got_method_query);
}

test "ObjectPool basic object create/destroy cycle" {
    var pool = TestPool.init(std.testing.allocator);
    defer pool.deinit();

    var test_obj = TestObject{};

    const handle = try pool.createObject(&test_obj);

    try std.testing.expectEqual(false, test_obj.got_destroy_call);
    try std.testing.expectEqual(false, test_obj.got_method_query);

    try std.testing.expectEqual(true, pool.isObjectValid(handle));

    _ = try pool.getMethod(handle, "irrelevant");

    try std.testing.expectEqual(false, test_obj.got_destroy_call);
    try std.testing.expectEqual(true, test_obj.got_method_query);

    pool.destroyObject(handle);

    try std.testing.expectEqual(true, test_obj.got_destroy_call);
    try std.testing.expectEqual(true, test_obj.got_method_query);

    try std.testing.expectEqual(false, pool.isObjectValid(handle));
}

test "ObjectPool automatic cleanup" {
    var pool = TestPool.init(std.testing.allocator);
    errdefer pool.deinit();

    var test_obj = TestObject{};

    const handle = try pool.createObject(&test_obj);

    try std.testing.expectEqual(false, test_obj.got_destroy_call);
    try std.testing.expectEqual(false, test_obj.got_method_query);

    try std.testing.expectEqual(true, pool.isObjectValid(handle));

    pool.deinit();

    try std.testing.expectEqual(true, test_obj.got_destroy_call);
    try std.testing.expectEqual(false, test_obj.got_method_query);
}

test "ObjectPool garbage collection" {
    var pool = TestPool.init(std.testing.allocator);
    defer pool.deinit();

    var test_obj = TestObject{};

    const handle = try pool.createObject(&test_obj);

    try std.testing.expectEqual(false, test_obj.got_destroy_call);
    try std.testing.expectEqual(true, pool.isObjectValid(handle));

    // Prevent the object from being collected because it is marked as used
    pool.clearUsageCounters();
    try pool.markUsed(handle);
    pool.collectGarbage();

    try std.testing.expectEqual(false, test_obj.got_destroy_call);
    try std.testing.expectEqual(true, pool.isObjectValid(handle));

    // Prevent the object from being collected because it is marked as referenced
    try pool.retainObject(handle);
    pool.clearUsageCounters();
    pool.collectGarbage();
    try pool.releaseObject(handle);

    try std.testing.expectEqual(false, test_obj.got_destroy_call);
    try std.testing.expectEqual(true, pool.isObjectValid(handle));

    // Destroy the object by not marking it referenced at last
    pool.clearUsageCounters();
    pool.collectGarbage();

    try std.testing.expectEqual(true, test_obj.got_destroy_call);
    try std.testing.expectEqual(false, pool.isObjectValid(handle));
}

// TODO: Write tests for walkEnvironment and walkVM

test "ObjectPool serialization" {
    var backing_buffer: [1024]u8 = undefined;

    const serialized_id = blk: {
        var pool = TestPool.init(std.testing.allocator);
        defer pool.deinit();

        var test_obj = TestObject{};
        const id = try pool.createObject(&test_obj);

        try std.testing.expectEqual(false, test_obj.was_serialized);

        var fbs = std.Io.Writer.fixed(&backing_buffer);
        try pool.serialize(&fbs);

        try std.testing.expectEqual(true, test_obj.was_serialized);

        break :blk id;
    };

    {
        var fbs = std.Io.Reader.fixed(&backing_buffer);

        try std.testing.expectEqual(false, TestObject.deserialize_instance.was_deserialized);

        var pool = try TestPool.deserialize(std.testing.allocator, &fbs);
        defer pool.deinit();

        try std.testing.expectEqual(true, TestObject.deserialize_instance.was_deserialized);

        try std.testing.expect(pool.isObjectValid(serialized_id));
    }
}
