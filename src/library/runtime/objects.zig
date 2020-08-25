const std = @import("std");

usingnamespace @import("environment.zig");
usingnamespace @import("vm.zig");
usingnamespace @import("value.zig");

/// Non-owning interface to a abstract LoLa object.
/// It is associated with a object handle in the `ObjectPool` and provides
/// a way to get methods as well as destroy the object when it's garbage collected.
pub const Object = struct {
    const Self = @This();
    const ErasedSelf = @Type(.Opaque);

    /// Type-erased self-pointer that was passed to `init()`.
    erased_self: *ErasedSelf,

    /// Returns a method named `name` or `null` if none exists.
    /// The returned `Function` is non-owned and should have a `null` constructor,
    /// as it is never called by the virtual machine!
    getMethodFn: fn (*ErasedSelf, name: []const u8) ?Function,

    /// This is called when the object is removed from the associated object pool.
    destroyObjectFn: fn (*ErasedSelf) void,

    pub fn init(ref: anytype) Self {
        const PtrType = @TypeOf(ref);
        const info = @typeInfo(PtrType);
        std.debug.assert(info == .Pointer);

        const Impl = struct {
            fn getMethod(eself: *ErasedSelf, name: []const u8) ?Function {
                return @ptrCast(PtrType, @alignCast(info.Pointer.alignment, eself)).getMethod(name);
            }

            fn destroyObject(eself: *ErasedSelf) void {
                @ptrCast(PtrType, @alignCast(info.Pointer.alignment, eself)).destroyObject();
            }
        };

        return Self{
            .erased_self = @ptrCast(*ErasedSelf, ref),
            .getMethodFn = Impl.getMethod,
            .destroyObjectFn = Impl.destroyObject,
        };
    }

    pub fn getMethod(self: Self, name: []const u8) ?Function {
        return self.getMethodFn(self.erased_self, name);
    }

    pub fn destroyObject(self: *Self) void {
        self.destroyObjectFn(self.erased_self);
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
pub const ObjectPool = struct {
    const Self = @This();

    const ManagedObject = struct {
        refcount: usize,
        manualRefcount: usize,
        object: Object,
    };

    const ObjectGetError = error{InvalidObject};

    objectCounter: u64,
    objects: std.AutoHashMap(ObjectHandle, ManagedObject),

    // Initializer API
    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .objectCounter = 0,
            .objects = std.AutoHashMap(ObjectHandle, ManagedObject).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.objects.iterator();
        while (iter.next()) |obj| {
            obj.value.object.destroyObject();
        }
        self.objects.deinit();
    }

    // Public API

    /// Serializes a object handle
    pub fn serialize(self: Self, stream: anytype, object: ObjectHandle) !void {
        // TODO: Implement object serialization/deserialization API
        @panic("not implemented yet!");
    }

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
};

const TestObject = struct {
    const Self = @This();

    got_method_query: bool = false,
    got_destroy_call: bool = false,

    fn getMethod(self: *Self, name: []const u8) ?Function {
        self.got_method_query = true;
        return null;
    }

    /// This is called when the object is removed from the associated object pool.
    fn destroyObject(self: *Self) void {
        self.got_destroy_call = true;
    }
};

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
    var pool = ObjectPool.init(std.testing.allocator);
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
    var pool = ObjectPool.init(std.testing.allocator);
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
    var pool = ObjectPool.init(std.testing.allocator);
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
