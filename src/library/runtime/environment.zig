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
    /// This is a reference to the environment for that function.
    /// If the environment is `null`, the environment is context-sensitive
    /// and will always be the environment that provided that function.
    /// This is a "workaround" for not storing a pointer-to-self in Environment for
    /// embedded script functions.
    environment: ?*Environment,
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

    fn zigTypeToLoLa(comptime T: type) TypeId {
        const info = @typeInfo(T);
        if (info == .Int)
            return TypeId.number;
        if (info == .Float)
            return TypeId.number;
        return switch (T) {
            bool => TypeId.boolean,
            ObjectHandle => TypeId.object,
            void => TypeId.void,
            []const u8 => TypeId.string,
            else => @compileError(@typeName(T) ++ " is not a wrappable type!"),
        };
    }

    fn convertToZigValue(comptime Target: type, value: Value) !Target {
        const info = @typeInfo(Target);
        if (info == .Int)
            return try value.toInteger(Target);
        if (info == .Float)
            return @floatCast(Target, try value.toNumber());
        return switch (Target) {
            // Native types
            void => try value.toVoid(),
            bool => try value.toBoolean(),
            []const u8 => value.toString(),

            // LoLa types
            ObjectHandle => try value.toObject(),
            String => if (value == .string)
                value.string
            else
                return error.TypeMismatch,
            Array => value.toArray(),

            Value => value,

            else => @compileError(@typeName(T) ++ " is not a wrappable type!"),
        };
    }

    fn convertToLoLaValue(allocator: *std.mem.Allocator, value: anytype) !Value {
        const T = @TypeOf(value);
        const info = @typeInfo(T);
        if (info == .Int)
            return Value.initInteger(T, value);
        if (info == .Float)
            return Value.initNumber(value);
        return switch (T) {
            // Native types
            void => .void,
            bool => Value.initBoolean(value),
            []const u8 => try Value.initString(allocator, value),

            // LoLa types
            ObjectHandle => Value.initObject(value),
            String => Value.fromString(value),
            Array => Value.fromArray(value),

            Value => value,

            else => @compileError(@typeName(T) ++ " is not a wrappable type!"),
        };
    }

    /// Wraps a native zig function into a LoLa function.
    /// The function may take any number of arguments of supported types and return one of those as well.
    /// Supported types are:
    /// - `lola.runtime.Value`
    /// - `lola.runtime.String`
    /// - `lola.runtime.Array`
    /// - `lola.runtime.ObjectHandle`
    /// - any integer type
    /// - any floating point type
    /// - `bool`
    /// - `void`
    /// - `[]const u8`
    /// Note that when you receive arguments, you don't own them. Do not free or store String or Array values.
    /// When you return a String or Array, you hand over ownership of that value to the LoLa vm.
    pub fn wrap(comptime function: anytype) Function {
        const F = @TypeOf(function);
        const info = @typeInfo(F);
        if (info != .Fn)
            @compileError("Function.wrap expects a function!");

        const function_info = info.Fn;
        if (function_info.is_generic)
            @compileError("Cannot wrap generic functions!");
        if (function_info.is_var_args)
            @compileError("Cannot wrap functions with variadic arguments!");

        const ArgsTuple = comptime blk: {
            var argument_field_list: [function_info.args.len]std.builtin.TypeInfo.StructField = undefined;
            inline for (function_info.args) |arg, i| {
                var num_buf: [128]u8 = undefined;
                argument_field_list[i] = std.builtin.TypeInfo.StructField{
                    .name = std.fmt.bufPrint(&num_buf, "{d}", .{i}) catch unreachable,
                    .field_type = arg.arg_type.?,
                    .default_value = @as(?(arg.arg_type.?), null),
                    .is_comptime = false,
                };
            }

            break :blk @Type(std.builtin.TypeInfo{
                .Struct = std.builtin.TypeInfo.Struct{
                    .is_tuple = true,
                    .layout = .Auto,
                    .decls = &[_]std.builtin.TypeInfo.Declaration{},
                    .fields = &argument_field_list,
                },
            });
        };

        const Impl = struct {
            fn invoke(env: *Environment, context: Context, args: []const Value) anyerror!Value {
                if (args.len != function_info.args.len)
                    return error.InvalidArgs;

                var zig_args: ArgsTuple = undefined;

                comptime var index = 0;
                while (index < function_info.args.len) : (index += 1) {
                    const T = function_info.args[index].arg_type.?;
                    zig_args[index] = try convertToZigValue(T, args[index]);
                }

                const ReturnType = function_info.return_type.?;

                const ActualReturnType = switch (@typeInfo(ReturnType)) {
                    .ErrorUnion => |eu| eu.payload,
                    else => ReturnType,
                };

                var result: ActualReturnType = if (ReturnType != ActualReturnType)
                    try @call(.{}, function, zig_args)
                else
                    @call(.{}, function, zig_args);

                return try convertToLoLaValue(env.allocator, result);
            }
        };

        return initSimpleUser(Impl.invoke);
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
    objectPool: ObjectPoolInterface,

    /// Stores all available named globals.
    /// Globals will be contained in this unit and will be deinitialized,
    /// the name must be kept alive until end of the environment.
    namedGlobals: std.StringHashMap(NamedGlobal),

    /// Stores all available global functions.
    /// Functions will be contained in this unit and will be deinitialized,
    /// the name must be kept alive until end of the environment.
    functions: std.StringHashMap(Function),

    /// This is called when the destroyObject is called.
    destructor: ?fn (self: *Environment) void,

    pub fn init(allocator: *std.mem.Allocator, compileUnit: *const CompileUnit, object_pool: ObjectPoolInterface) !Self {
        var self = Self{
            .allocator = allocator,
            .compileUnit = compileUnit,
            .objectPool = object_pool,
            .scriptGlobals = undefined,
            .namedGlobals = undefined,
            .functions = undefined,
            .destructor = null,
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
                    .environment = null, // this is a "self-contained" script function
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

    // Implementation to make a Environment a valid LoLa object:
    pub fn getMethod(self: *Self, name: []const u8) ?Function {
        if (self.functions.get(name)) |fun| {
            var mut_fun = fun;
            if (mut_fun == .script and mut_fun.script.environment == null)
                mut_fun.script.environment = self;
            return mut_fun;
        } else {
            return null;
        }
    }

    /// This is called when the object is removed from the associated object pool.
    pub fn destroyObject(self: *Self) void {
        if (self.destructor) |dtor| {
            dtor(self);
        }
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

    var pool = ObjectPool(.{}).init(std.testing.allocator);
    defer pool.deinit();

    var env = try Environment.init(std.testing.allocator, &cu, pool.interface());
    defer env.deinit();

    std.debug.assert(env.scriptGlobals.len == 4);

    std.debug.assert(env.functions.count() == 3);

    const f1 = env.getMethod("fun1") orelse unreachable;
    const f2 = env.getMethod("fun_2") orelse unreachable;
    const f3 = env.getMethod("fun 3") orelse unreachable;

    std.testing.expectEqual(@as(usize, 10), f1.script.entryPoint);
    std.testing.expectEqual(@as(usize, 5), f1.script.localCount);
    std.testing.expectEqual(&env, f1.script.environment.?);

    std.testing.expectEqual(@as(usize, 21), f2.script.entryPoint);
    std.testing.expectEqual(@as(usize, 1), f2.script.localCount);
    std.testing.expectEqual(&env, f2.script.environment.?);

    std.testing.expectEqual(@as(usize, 32), f3.script.entryPoint);
    std.testing.expectEqual(@as(usize, 3), f3.script.localCount);
    std.testing.expectEqual(&env, f3.script.environment.?);
}

test "Function.wrap" {
    const Funcs = struct {
        fn returnVoid() void {
            unreachable;
        }
        fn returnValue() Value {
            unreachable;
        }
        fn returnString() String {
            unreachable;
        }
        fn returnArray() Array {
            unreachable;
        }
        fn returnObjectHandle() ObjectHandle {
            unreachable;
        }
        fn returnInt8() u8 {
            unreachable;
        }
        fn returnInt63() i63 {
            unreachable;
        }
        fn returnF64() f64 {
            unreachable;
        }
        fn returnF16() f16 {
            unreachable;
        }
        fn returnBool() bool {
            unreachable;
        }
        fn returnStringLit() []const u8 {
            unreachable;
        }

        fn takeVoid(value: void) void {
            unreachable;
        }
        fn takeValue(value: Value) void {
            unreachable;
        }
        fn takeString(value: String) void {
            unreachable;
        }
        fn takeArray(value: Array) void {
            unreachable;
        }
        fn takeObjectHandle(value: ObjectHandle) void {
            unreachable;
        }
        fn takeInt8(value: u8) void {
            unreachable;
        }
        fn takeInt63(value: i63) void {
            unreachable;
        }
        fn takeF64(value: f64) void {
            unreachable;
        }
        fn takeF16(value: f16) void {
            unreachable;
        }
        fn takeBool(value: bool) void {
            unreachable;
        }
        fn takeStringLit(value: []const u8) void {
            unreachable;
        }

        fn takeAll(
            a0: Value,
            a1: String,
            a2: Array,
            a3: ObjectHandle,
            a4_1: u7,
            a4_2: i33,
            a5_1: f32,
            a5_2: f16,
            a6: bool,
            a7: void,
            a8: []const u8,
        ) void {
            unreachable;
        }
    };

    inline for (std.meta.declarations(Funcs)) |fun| {
        _ = Function.wrap(@field(Funcs, fun.name));
    }
}
