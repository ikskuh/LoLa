const std = @import("std");
const iface = @import("interface");

const utility = @import("utility.zig");

// Import modules to reduce file size
usingnamespace @import("value.zig");
usingnamespace @import("../common/compile-unit.zig");
usingnamespace @import("named_global.zig");
usingnamespace @import("context.zig");
usingnamespace @import("vm.zig");
usingnamespace @import("objects.zig");

/// A script function contained in either this or a foreign
/// environment. For foreign environments.
pub const ScriptFunction = struct {
    compileUnit: *const CompileUnit,
    entryPoint: u32,
    localCount: u16,
};

const UserFunctionCall = fn (
    environment: *Environment,
    context: Context,
    args: []const Value,
) anyerror!Value;

/// A synchronous function that may be called from the script environment
pub const UserFunction = struct {
    const Self = @This();

    /// Context, will be passed to `call`.
    context: Context,

    /// Executes the function, returns a value synchronously.
    call: UserFunctionCall,

    /// Optional destructor that may free the memory stored in `context`.
    /// Is called when the function call is deinitialized.
    destructor: ?fn (context: Context) void,

    pub fn deinit(self: *Self) void {
        if (self.destructor) |dtor| {
            dtor(self.context);
        }
        self.* = undefined;
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

    pub fn deinit(self: *Self) void {
        if (self.destructor) |dtor| {
            dtor(self.context);
        }
        self.* = undefined;
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

    pub fn deinit(self: *Self) void {
        if (self.destructor) |dtor| {
            dtor(self.context);
        }
        self.* = undefined;
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
    const Self = @This();

    /// This is another function of a script. It may be a foreign
    /// or local script to the environment.
    script: ScriptFunction,

    /// A synchronous function like `Sin` that executes in very short time.
    syncUser: UserFunction,

    /// An asynchronous function that will yield the VM execution.
    asyncUser: AsyncUserFunction,

    pub fn initSimpleUser(fun: fn (env: *Environment, context: Context, args: []const Value) anyerror!Value) Function {
        return Self{
            .syncUser = UserFunction{
                .context = Context.initVoid(),
                .destructor = null,
                .call = fun,
            },
        };
    }

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .script => {},
            .syncUser => |*f| f.deinit(),
            .asyncUser => |*f| f.deinit(),
        }
    }
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
    objectPool: *ObjectPool,

    /// Stores all available named globals.
    /// Globals will be contained in this unit and will be deinitialized,
    /// the name must be kept alive until end of the environment.
    namedGlobals: std.StringHashMap(NamedGlobal),

    /// Stores all available global functions.
    /// Functions will be contained in this unit and will be deinitialized,
    /// the name must be kept alive until end of the environment.
    functions: std.StringHashMap(Function),

    pub fn init(allocator: *std.mem.Allocator, compileUnit: *const CompileUnit, object_pool: *ObjectPool) !Self {
        var self = Self{
            .allocator = allocator,
            .compileUnit = compileUnit,
            .objectPool = object_pool,
            .scriptGlobals = undefined,
            .namedGlobals = undefined,
            .functions = undefined,
        };

        self.scriptGlobals = try allocator.alloc(Value, compileUnit.globalCount);
        errdefer allocator.free(self.scriptGlobals);

        for (self.scriptGlobals) |*glob| {
            glob.* = .void;
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

    pub fn deinit(self: *Self) void {
        var iter = self.functions.iterator();
        while (iter.next()) |fun| {
            fun.value.deinit();
        }

        for (self.scriptGlobals) |*glob| {
            glob.deinit();
        }

        self.namedGlobals.deinit();
        self.functions.deinit();
        self.allocator.free(self.scriptGlobals);

        self.* = undefined;
    }

    /// Adds a function to the environment and makes it available for the script.
    pub fn installFunction(self: *Self, name: []const u8, function: Function) !void {
        var result = try self.functions.getOrPut(name);
        if (result.found_existing)
            return error.AlreadyExists;
        result.entry.value = function;
    }

    /// Adds a named global to the environment and makes it available for the script.
    /// Import this with `extern`
    pub fn addGlobal(self: *Self, name: []const u8, value: Value) !void {
        var result = try self.namedGlobals.getOrPut(name);
        if (result.found_existing)
            return error.AlreadyExists;
        result.entry.value = NamedGlobal.initStored(value);
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

    var pool = ObjectPool.init(std.testing.allocator);
    defer pool.deinit();

    var env = try Environment.init(std.testing.allocator, &cu, &pool);
    defer env.deinit();

    std.debug.assert(env.scriptGlobals.len == 4);

    std.debug.assert(env.functions.count() == 3);

    const f1 = env.functions.get("fun1") orelse unreachable;
    const f2 = env.functions.get("fun_2") orelse unreachable;
    const f3 = env.functions.get("fun 3") orelse unreachable;

    std.debug.assert(f1.script.entryPoint == 10);
    std.debug.assert(f1.script.localCount == 5);
    std.debug.assert(f1.script.compileUnit == &cu);

    std.debug.assert(f2.script.entryPoint == 21);
    std.debug.assert(f2.script.localCount == 1);
    std.debug.assert(f2.script.compileUnit == &cu);

    std.debug.assert(f3.script.entryPoint == 32);
    std.debug.assert(f3.script.localCount == 3);
    std.debug.assert(f3.script.compileUnit == &cu);
}
