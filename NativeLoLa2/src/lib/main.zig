const std = @import("std");

const utility = @import("utility.zig");

// Import modules to reduce file size
usingnamespace @import("value.zig");
usingnamespace @import("ir.zig");
usingnamespace @import("compile_unit.zig");
usingnamespace @import("decoder.zig");
usingnamespace @import("named_global.zig");
usingnamespace @import("disassembler.zig");

/// Reference to an abstract object.
pub const ObjectHandle = u64;

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
    context: []const u8,

    /// Executes the function, returns a value synchronously.
    call: fn (context: []const u8, args: []const Value) anyerror!Value,

    /// Optional destructor that may free the memory stored in `context`.
    /// Is called when the function call is deinitialized.
    destructor: ?fn (self: Self) void,

    fn deinit(self: Self) void {
        if (self.destructor) |dtor| {
            dtor(self);
        }
    }
};

test "UserFunction (destructor)" {
    var uf1: UserFunction = .{
        .context = "Hello",
        .call = undefined,
        .destructor = null,
    };
    defer uf1.deinit();

    var uf2: UserFunction = .{
        .context = try std.mem.dupe(std.testing.allocator, u8, "Hello"),
        .call = undefined,
        .destructor = struct {
            fn destructor(uf: UserFunction) void {
                std.testing.allocator.free(uf.context);
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
    context: []const u8,

    /// Begins execution of this function.
    /// After the initialization, the return value will be invoked once
    /// to check if the function can finish synchronously.
    call: fn (context: []const u8, args: []const Value) anyerror!AsyncFunctionCall,

    /// Optional destructor that may free the memory stored in `context`.
    /// Is called when the function call is deinitialized.
    destructor: ?fn (self: Self) void,

    fn deinit(self: Self) void {
        if (self.destructor) |dtor| {
            dtor(self);
        }
    }
};

test "AsyncUserFunction (destructor)" {
    var uf1: AsyncUserFunction = .{
        .context = "Hello",
        .call = undefined,
        .destructor = null,
    };
    defer uf1.deinit();

    var uf2: AsyncUserFunction = .{
        .context = try std.mem.dupe(std.testing.allocator, u8, "Hello"),
        .call = undefined,
        .destructor = struct {
            fn destructor(uf: AsyncUserFunction) void {
                std.testing.allocator.free(uf.context);
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
    object: ?ObjectHandle,

    /// The context may be used to to store the state of this function call.
    /// This may be created with `@sliceToBytes`.
    context: []u8,

    /// Executor that will run this function call.
    /// May return a value (function call completed) or `null` (function call still in progress).
    execute: fn (self: Self) anyerror!?Value,

    /// Optional destructor that may free the memory stored in `context`.
    /// Is called when the function call is deinitialized.
    destructor: ?fn (self: Self) void,

    fn deinit(self: Self) void {
        if (self.destructor) |dtor| {
            dtor(self);
        }
    }
};

test "AsyncFunctionCall.deinit" {
    const Helper = struct {
        fn destroy(self: AsyncFunctionCall) void {
            std.testing.allocator.free(self.context);
        }
        fn exec(self: AsyncFunctionCall) anyerror!?Value {
            return error.NotSupported;
        }
    };

    var callWithDtor = AsyncFunctionCall{
        .object = null,
        .context = try std.mem.dupe(std.testing.allocator, u8, "Hello!"),
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

/// The interface to provide access to scriptable objects.
pub const ObjectInterface = struct {
    const Self = @This();

    /// Context that will be passed to all functions.
    context: []const u8,

    /// Resolves the given object `name` to an identifier.
    /// Returns `null` if the object was not found.
    resolveObject: fn (context: []const u8, name: []const u8) ?ObjectHandle,

    /// Returns `true` if `handle` is still a valid object reference.
    isHandleValid: fn (context: []const u8, object: ObjectHandle) bool,

    /// Returns a function for the given object or `null` if the object does not have this function.
    /// Note that the returned function is non-owned and **must not** be deinitialized!
    getFunction: fn (context: []const u8, object: ObjectHandle, name: []const u8) error{ObjectNotFound}!?Function,

    /// Returns an object interface that does not provide any objects at all.
    pub const empty = Self{
        .context = undefined,
        .resolveObject = struct {
            fn f(ctx: []const u8, name: []const u8) ?ObjectHandle {
                return null;
            }
        }.f,
        .isHandleValid = struct {
            fn f(ctx: []const u8, h: ObjectHandle) bool {
                return false;
            }
        }.f,
        .getFunction = struct {
            fn f(context: []const u8, object: ObjectHandle, name: []const u8) error{ObjectNotFound}!?Function {
                return error.ObjectNotFound;
            }
        }.f,
    };
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
    objectInterface: ObjectInterface,

    /// Stores all available named globals.
    /// Globals will be contained in this unit and will be deinitialized,
    /// the name must be kept alive until end of the environment.
    namedGlobals: std.StringHashMap(NamedGlobal),

    /// Stores all available global functions.
    /// Functions will be contained in this unit and will be deinitialized,
    /// the name must be kept alive until end of the environment.
    functions: std.StringHashMap(Function),

    fn init(allocator: *std.mem.Allocator, compileUnit: *const CompileUnit, objectInterface: ObjectInterface) !Self {
        var self = Self{
            .allocator = allocator,
            .compileUnit = compileUnit,
            .objectInterface = objectInterface,
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

    fn deinit(self: Self) void {
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
    }
};

test "Environment" {
    const cu = CompileUnit{
        .arena = undefined,
        .comment = "",
        .globalCount = 4,
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

    var env = try Environment.init(std.testing.allocator, &cu, ObjectInterface.empty);
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
