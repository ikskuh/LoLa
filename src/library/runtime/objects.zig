const std = @import("std");
const interfaces = @import("interface");

usingnamespace @import("environment.zig");
usingnamespace @import("vm.zig");
usingnamespace @import("value.zig");

/// Non-owning interface to a abstract LoLa object.
/// It is associated with a object handle in the `ObjectPool` and provides
/// a way to get methods as well as destroy the object when it's garbage collected.
pub const Object = struct {
    const Interface = interfaces.Interface(struct {
        getMethod: fn (self: *interfaces.SelfType, name: []const u8) ?Function,
        destroyObject: fn (self: *interfaces.SelfType) void,
    }, interfaces.Storage.NonOwning);

    const Class = interfaces.Interface(struct {
        serializeObject: ?fn (self: *interfaces.SelfType, stream: OutputStream) anyerror!void,
        deserializeObject: ?fn (stream: InputStream) anyerror!*interfaces.SelfType,
    }, interfaces.Storage.NonOwning);

    const Self = @This();

    impl: Interface,

    pub fn init(ptr: anytype) Self {
        return Self{
            .impl = Interface.init(ptr) catch unreachable,
        };
    }
    fn getMethod(self: *const Self, name: []const u8) ?Function {
        return self.impl.call("getMethod", .{name});
    }

    fn destroyObject(self: *Self) void {
        self.impl.call("destroyObject", .{});
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
    pub const ErasedSelf = @Type(.Opaque);

    self: *ErasedSelf,
    read: fn (self: *ErasedSelf, buf: []u8) anyerror!usize,

    fn readSome(self: Self, buffer: []u8) anyerror!usize {
        return self.read(self.self, buffer);
    }

    pub const Reader = std.io.Reader(Self, anyerror, readSome);
};

pub const OutputStream = struct {
    const Self = @This();
    pub const ErasedSelf = @Type(.Opaque);

    self: *ErasedSelf,
    write: fn (self: *ErasedSelf, buf: []const u8) anyerror!usize,

    fn writeSome(self: Self, buffer: []const u8) anyerror!usize {
        return self.read(self.self, buffer);
    }

    pub const Writer = std.io.Writer(Self, anyerror, writeSome);
};

const ObjectGetError = error{InvalidObject};

pub const ObjectPoolInterface = struct {
    const ErasedSelf = @Type(.Opaque);

    self: *ErasedSelf,

    getMethodFn: fn (self: *ErasedSelf, handle: ObjectHandle, name: []const u8) ObjectGetError!?Function,
    destroyObjectFn: fn (self: *ErasedSelf, handle: ObjectHandle) void,
    isObjectValidFn: fn (self: *ErasedSelf, handle: ObjectHandle) bool,

    pub fn getMethod(self: @This(), handle: ObjectHandle, name: []const u8) ObjectGetError!?Function {
        return self.getMethodFn(self.self, handle, name);
    }
    pub fn destroyObject(self: @This(), handle: ObjectHandle) void {
        return self.destroyObjectFn(self.self, handle);
    }
    pub fn isObjectValid(self: @This(), handle: ObjectHandle) bool {
        return self.isObjectValidFn(self.self, handle);
    }
    pub fn serialize(self: @This(), stream: anytype, handle: ObjectHandle) !void {
        unreachable;
    }
    pub fn deserialize(self: @This(), stream: anytype) !ObjectHandle {
        unreachable;
    }

    pub fn castTo(self: *@This(), comptime PoolType: type) *PoolType {
        return @ptrCast(*PoolType, @alignCast(@alignOf(PoolType), self.self));
    }
};

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
    comptime var classes: [classes_list.len]type = undefined;
    for (classes_list) |item, i| {
        classes[i] = item;
    }

    comptime var hasher = std.hash.SipHash64(2, 4).init("ObjectPool Serialization Version 1");

    inline for (classes) |class| {
        if (@hasDecl(class, "serializeObject") != @hasDecl(class, "deserializeObject")) {
            @compileError("Each class requires either both serializeObject and deserializeObject to be present or none.");
        }
        // this requires to use a typeHash structure instead of the type name
        hasher.update(@typeName(class));
    }

    const pool_signature = hasher.finalInt();

    return struct {
        const Self = @This();

        const ManagedObject = struct {
            refcount: usize,
            manualRefcount: usize,
            object: Object,
        };

        /// ever-increasing number which is used to allocate new object handles.
        objectCounter: u64,

        /// stores all alive objects. Removing elements from this
        /// requires to call `.object.destroyObject()`!
        objects: std.AutoHashMap(ObjectHandle, ManagedObject),

        /// Creates a new object pool, using `allocator` to handle hashmap allocations.
        pub fn init(allocator: *std.mem.Allocator) Self {
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
                obj.value.object.destroyObject();
            }
            self.objects.deinit();
            self.* = undefined;
        }

        // Public API

        /// Serializes a object handle into the `stream` or returns a error.NotSupported.
        pub fn serialize(self: Self, stream: anytype, object: ObjectHandle) !void {
            // TODO: Implement object serialization/deserialization API
            @panic("not implemented yet!");
        }

        /// Deserializes a new object from `steam` and returns its object handle.
        /// May return `error.NotSupported` when the ObjectPool does not support
        /// object serialization/deserialization.
        pub fn deserialize(self: Self, stream: anytype) !ObjectHandle {
            // TODO: Implement object serialization/deserialization API
            @panic("not implemented yet!");
        }

        /// Inserts a new object into the pool and returns a handle to it.
        pub fn createObject(self: *Self, object: Object) !ObjectHandle {
            self.objectCounter += 1;
            const handle = @intToEnum(ObjectHandle, self.objectCounter);
            try self.objects.putNoClobber(handle, ManagedObject{
                .object = object,
                .refcount = 0,
                .manualRefcount = 0,
            });
            return handle;
        }

        /// Keeps the object from beeing garbage collected.
        /// To allow recollection, call `releaseObject`.
        pub fn retainObject(self: *Self, object: ObjectHandle) ObjectGetError!void {
            if (self.objects.getEntry(object)) |obj| {
                obj.value.manualRefcount += 1;
            } else {
                return error.InvalidObject;
            }
        }

        /// Removes a restrain from `retainObject` to re-allow garbage collection.
        pub fn releaseObject(self: *Self, object: ObjectHandle) ObjectGetError!void {
            if (self.objects.getEntry(object)) |obj| {
                obj.value.manualRefcount -= 1;
            } else {
                return error.InvalidObject;
            }
        }

        /// Destroys an object by external means. This will also invoke the object destructor.
        pub fn destroyObject(self: *Self, object: ObjectHandle) void {
            if (self.objects.remove(object)) |obj| {
                var copy = obj.value.object;
                copy.destroyObject();
            }
        }

        /// Returns if an object handle is still valid.
        pub fn isObjectValid(self: Self, object: ObjectHandle) bool {
            return if (self.objects.get(object)) |obj| true else false;
        }

        /// Gets the method of an object or `null` if the method does not exist.
        /// The returned `Function` is non-owned.
        pub fn getMethod(self: Self, object: ObjectHandle, name: []const u8) ObjectGetError!?Function {
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
                obj.value.refcount = 0;
            }
        }

        /// Marks an object handle as used
        pub fn markUsed(self: *Self, object: ObjectHandle) ObjectGetError!void {
            if (self.objects.getEntry(object)) |obj| {
                obj.value.refcount += 1;
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
        pub fn walkVM(self: *Self, vm: VM) ObjectGetError!void {
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
                if (obj.value.refcount == 0 and obj.value.manualRefcount == 0) {
                    if (self.objects.remove(obj.key)) |kv| {
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
                    return @ptrCast(*Self, @alignCast(@alignOf(Self), erased_self));
                }
                fn getMethod(erased_self: *ErasedSelf, handle: ObjectHandle, name: []const u8) ObjectGetError!?Function {
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
                .self = @ptrCast(*ObjectPoolInterface.ErasedSelf, self),
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

    pub fn getMethod(self: *Self, name: []const u8) ?Function {
        self.got_method_query = true;
        return null;
    }

    /// This is called when the object is removed from the associated object pool.
    pub fn destroyObject(self: *Self) void {
        self.got_destroy_call = true;
    }
};

const TestPool = ObjectPool([_]type{TestObject});

test "Object" {
    var test_obj = TestObject{};
    var object = Object.init(&test_obj);

    std.testing.expectEqual(false, test_obj.got_destroy_call);
    std.testing.expectEqual(false, test_obj.got_method_query);

    _ = object.getMethod("irrelevant");

    std.testing.expectEqual(false, test_obj.got_destroy_call);
    std.testing.expectEqual(true, test_obj.got_method_query);

    object.destroyObject();

    std.testing.expectEqual(true, test_obj.got_destroy_call);
    std.testing.expectEqual(true, test_obj.got_method_query);
}

test "ObjectPool basic object create/destroy cycle" {
    var pool = TestPool.init(std.testing.allocator);
    defer pool.deinit();

    var test_obj = TestObject{};

    const handle = try pool.createObject(Object.init(&test_obj));

    std.testing.expectEqual(false, test_obj.got_destroy_call);
    std.testing.expectEqual(false, test_obj.got_method_query);

    std.testing.expectEqual(true, pool.isObjectValid(handle));

    _ = try pool.getMethod(handle, "irrelevant");

    std.testing.expectEqual(false, test_obj.got_destroy_call);
    std.testing.expectEqual(true, test_obj.got_method_query);

    pool.destroyObject(handle);

    std.testing.expectEqual(true, test_obj.got_destroy_call);
    std.testing.expectEqual(true, test_obj.got_method_query);

    std.testing.expectEqual(false, pool.isObjectValid(handle));
}

test "ObjectPool automatic cleanup" {
    var pool = TestPool.init(std.testing.allocator);
    errdefer pool.deinit();

    var test_obj = TestObject{};

    const handle = try pool.createObject(Object.init(&test_obj));

    std.testing.expectEqual(false, test_obj.got_destroy_call);
    std.testing.expectEqual(false, test_obj.got_method_query);

    std.testing.expectEqual(true, pool.isObjectValid(handle));

    pool.deinit();

    std.testing.expectEqual(true, test_obj.got_destroy_call);
    std.testing.expectEqual(false, test_obj.got_method_query);
}

test "ObjectPool garbage collection" {
    var pool = TestPool.init(std.testing.allocator);
    defer pool.deinit();

    var test_obj = TestObject{};

    const handle = try pool.createObject(Object.init(&test_obj));

    std.testing.expectEqual(false, test_obj.got_destroy_call);
    std.testing.expectEqual(true, pool.isObjectValid(handle));

    // Prevent the object from being collected because it is marked as used
    pool.clearUsageCounters();
    try pool.markUsed(handle);
    pool.collectGarbage();

    std.testing.expectEqual(false, test_obj.got_destroy_call);
    std.testing.expectEqual(true, pool.isObjectValid(handle));

    // Prevent the object from being collected because it is marked as referenced
    try pool.retainObject(handle);
    pool.clearUsageCounters();
    pool.collectGarbage();
    try pool.releaseObject(handle);

    std.testing.expectEqual(false, test_obj.got_destroy_call);
    std.testing.expectEqual(true, pool.isObjectValid(handle));

    // Destroy the object by not marking it referenced at last
    pool.clearUsageCounters();
    pool.collectGarbage();

    std.testing.expectEqual(true, test_obj.got_destroy_call);
    std.testing.expectEqual(false, pool.isObjectValid(handle));
}

// TODO: Write tests for walkEnvironment and walkVM
