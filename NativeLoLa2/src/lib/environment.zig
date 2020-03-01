const std = @import("std");
const iface = @import("interface");

const utility = @import("utility.zig");

// Import modules to reduce file size
usingnamespace @import("value.zig");
usingnamespace @import("compile_unit.zig");
usingnamespace @import("named_global.zig");
usingnamespace @import("disassembler.zig");
usingnamespace @import("context.zig");

/// A script function contained in either this or a foreign
/// environment. For foreign environments.
pub const ScriptFunction = struct {
    compileUnit: *const CompileUnit,
    entryPoint: u32,
    localCount: u16,
};

/// A synchronous function that may be called from the script environment
pub const UserFunction = struct {
    const Self = @This();

    /// Context, will be passed to `call`.
    context: Context,

    /// Executes the function, returns a value synchronously.
    call: fn (context: Context, args: []const Value) anyerror!Value,

    /// Optional destructor that may free the memory stored in `context`.
    /// Is called when the function call is deinitialized.
    destructor: ?fn (context: Context) void,

    fn deinit(self: Self) void {
        if (self.destructor) |dtor| {
            dtor(self.context);
        }
    }
};

test "UserFunction (destructor)" {
    var uf1: UserFunction = .{
        .context = Context.initVoid(),
        .call = undefined,
        .destructor = null,
    };
    defer uf1.deinit();

    var uf2: UserFunction = .{
        .context = Context.init(u32, try std.testing.allocator.create(u32)),
        .call = undefined,
        .destructor = struct {
            fn destructor(ctx: Context) void {
                std.testing.allocator.destroy(ctx.get(u32));
            }
        }.destructor,
    };
    defer uf2.deinit();
}

/// An asynchronous function that yields execution of the VM
/// and can be resumed later.
pub const AsyncUserFunction = struct {
    const Self = @This();

    /// Context, will be passed to `call`.
    context: Context,

    /// Begins execution of this function.
    /// After the initialization, the return value will be invoked once
    /// to check if the function can finish synchronously.
    call: fn (context: Context, args: []const Value) anyerror!AsyncFunctionCall,

    /// Optional destructor that may free the memory stored in `context`.
    /// Is called when the function call is deinitialized.
    destructor: ?fn (context: Context) void,

    fn deinit(self: Self) void {
        if (self.destructor) |dtor| {
            dtor(self.context);
        }
    }
};

test "AsyncUserFunction (destructor)" {
    var uf1: AsyncUserFunction = .{
        .context = undefined,
        .call = undefined,
        .destructor = null,
    };
    defer uf1.deinit();

    var uf2: AsyncUserFunction = .{
        .context = Context.init(u32, try std.testing.allocator.create(u32)),
        .call = undefined,
        .destructor = struct {
            fn destructor(ctx: Context) void {
                std.testing.allocator.destroy(ctx.get(u32));
            }
        }.destructor,
    };
    defer uf2.deinit();
}

/// An asynchronous execution state.
pub const AsyncFunctionCall = struct {
    const Self = @This();

    /// The object this call state is associated with. This is required to
    /// prevent calling functions that operate on dead objects.
    /// This field is set by the VM and should not be initialized by the creator
    /// of the call.
    object: ?ObjectHandle = null,

    /// The context may be used to to store the state of this function call.
    /// This may be created with `@sliceToBytes`.
    context: Context,

    /// Executor that will run this function call.
    /// May return a value (function call completed) or `null` (function call still in progress).
    execute: fn (context: Context) anyerror!?Value,

    /// Optional destructor that may free the memory stored in `context`.
    /// Is called when the function call is deinitialized.
    destructor: ?fn (context: Context) void,

    fn deinit(self: Self) void {
        if (self.destructor) |dtor| {
            dtor(self.context);
        }
    }
};

test "AsyncFunctionCall.deinit" {
    const Helper = struct {
        fn destroy(context: Context) void {
            std.testing.allocator.destroy(context.get(u32));
        }
        fn exec(context: Context) anyerror!?Value {
            return error.NotSupported;
        }
    };

    var callWithDtor = AsyncFunctionCall{
        .object = null,
        .context = Context.init(u32, try std.testing.allocator.create(u32)),
        .execute = Helper.exec,
        .destructor = Helper.destroy,
    };
    defer callWithDtor.deinit();

    var callNoDtor = AsyncFunctionCall{
        .object = null,
        .context = undefined,
        .execute = Helper.exec,
        .destructor = null,
    };
    defer callNoDtor.deinit();
}

/// A function that can be called by a script.
pub const Function = union(enum) {
    /// This is another function of a script. It may be a foreign
    /// or local script to the environment.
    script: ScriptFunction,

    /// A synchronous function like `Sin` that executes in very short time.
    syncUser: UserFunction,

    /// An asynchronous function that will yield the VM execution.
    asyncUser: AsyncUserFunction,

    fn deinit(self: @This()) void {
        switch (self) {
            .script => {},
            .syncUser => |f| f.deinit(),
            .asyncUser => |f| f.deinit(),
        }
    }
};

pub const Object = iface.Interface(struct {
    getMethod: fn (*iface.SelfType, name: []const u8) ?Function,
    destroyObject: fn (*iface.SelfType) void,
}, iface.Storage.NonOwning);

pub const ObjectHandle = u64;

pub const ObjectPool = struct {
    const Self = @This();

    objectCounter: ObjectHandle,
    objects: std.AutoHashMap(ObjectHandle, Object),

    // Initializer API
    fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .objectCounter = 0,
            .objects = std.AutoHashMap(ObjectHandle, Object).init(allocator),
        };
    }

    fn deinit(self: Self) void {
        var iter = self.objects.iterator();
        while (iter.next()) |obj| {
            obj.value.call("destroyObject", .{});
        }
        self.objects.deinit();
    }

    // Public API

    /// Inserts a new object into the pool
    fn createObject(self: *Self, object: Object) !ObjectHandle {
        self.objectCounter += 1;
        try self.objects.putNoClobber(self.objectCounter, object);
        return self.objectCounter;
    }

    /// Destroys an object by external means. This will also invoke the object destructor.
    fn destroyObject(self: *Self, object: ObjectHandle) void {
        if (self.objects.get(object)) |obj| {
            obj.value.call("destroyObject", .{});
        }
    }

    /// Returns if an object handle is still valid.
    fn isObjectValid(self: Self, object: ObjectHandle) bool {
        return if (self.objects.get(object)) |obj| true else false;
    }

    /// Gets the method of an object or `null` if the method does not exist.
    fn getMethod(self: Self, object: ObjectHandle, name: []const u8) !?Function {
        if (self.objects.get(object)) |obj| {
            return obj.value.call("getMethod", .{name});
        } else {
            return error.InvalidObject;
        }
    }

    // Garbage Collector API

    /// Sets all usage counters to zero.
    fn clearUsageCounters(self: *Self) void {}

    /// Marks an object handle as used
    fn markUsed(self: *Self, object: ObjectHandle) !void {}

    /// Removes and destroys all objects that are not marked as used.
    fn collectGarbage(self: *Self) void {}
};

/// An execution environment provides all needed
/// data to execute a compiled piece of code.
/// It stores its global variables, available functions
/// and available features.
pub const Environment = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,

    /// The compile unit that provides the executed script.
    compileUnit: *const CompileUnit,

    /// Global variables required by the script.
    scriptGlobals: []Value,

    /// Object interface to
    objectPool: ObjectPool,

    /// Stores all available named globals.
    /// Globals will be contained in this unit and will be deinitialized,
    /// the name must be kept alive until end of the environment.
    namedGlobals: std.StringHashMap(NamedGlobal),

    /// Stores all available global functions.
    /// Functions will be contained in this unit and will be deinitialized,
    /// the name must be kept alive until end of the environment.
    functions: std.StringHashMap(Function),

    pub fn init(allocator: *std.mem.Allocator, compileUnit: *const CompileUnit) !Self {
        var self = Self{
            .allocator = allocator,
            .compileUnit = compileUnit,
            .objectPool = ObjectPool.init(allocator),
            .scriptGlobals = undefined,
            .namedGlobals = undefined,
            .functions = undefined,
        };

        self.scriptGlobals = try allocator.alloc(Value, compileUnit.globalCount);
        errdefer allocator.free(self.scriptGlobals);

        for (self.scriptGlobals) |*glob| {
            glob.* = Value.initVoid();
        }

        self.functions = std.StringHashMap(Function).init(allocator);
        errdefer self.functions.deinit();

        for (compileUnit.functions) |srcfun| {
            var fun = Function{
                .script = ScriptFunction{
                    .compileUnit = compileUnit,
                    .entryPoint = srcfun.entryPoint,
                    .localCount = srcfun.localCount,
                },
            };
            _ = try self.functions.put(srcfun.name, fun);
        }

        self.namedGlobals = std.StringHashMap(NamedGlobal).init(allocator);
        errdefer self.namedGlobals.deinit();

        return self;
    }

    pub fn deinit(self: Self) void {
        var iter = self.functions.iterator();
        while (iter.next()) |fun| {
            fun.value.deinit();
        }

        for (self.scriptGlobals) |glob| {
            glob.deinit();
        }

        self.namedGlobals.deinit();
        self.functions.deinit();
        self.allocator.free(self.scriptGlobals);
        self.objectPool.deinit();
    }
};

test "Environment" {
    const cu = CompileUnit{
        .arena = undefined,
        .comment = "",
        .globalCount = 4,
        .temporaryCount = 0,
        .code = "",
        .functions = &[_]CompileUnit.Function{
            CompileUnit.Function{
                .name = "fun1",
                .entryPoint = 10,
                .localCount = 5,
            },
            CompileUnit.Function{
                .name = "fun_2",
                .entryPoint = 21,
                .localCount = 1,
            },
            CompileUnit.Function{
                .name = "fun 3",
                .entryPoint = 32,
                .localCount = 3,
            },
        },
        .debugSymbols = &[0]CompileUnit.DebugSymbol{},
    };

    var env = try Environment.init(std.testing.allocator, &cu);
    defer env.deinit();

    std.debug.assert(env.scriptGlobals.len == 4);

    std.debug.assert(env.functions.size == 3);

    const f1 = env.functions.get("fun1") orelse unreachable;
    const f2 = env.functions.get("fun_2") orelse unreachable;
    const f3 = env.functions.get("fun 3") orelse unreachable;

    std.debug.assert(f1.value.script.entryPoint == 10);
    std.debug.assert(f1.value.script.localCount == 5);
    std.debug.assert(f1.value.script.compileUnit == &cu);

    std.debug.assert(f2.value.script.entryPoint == 21);
    std.debug.assert(f2.value.script.localCount == 1);
    std.debug.assert(f2.value.script.compileUnit == &cu);

    std.debug.assert(f3.value.script.entryPoint == 32);
    std.debug.assert(f3.value.script.localCount == 3);
    std.debug.assert(f3.value.script.compileUnit == &cu);
}
