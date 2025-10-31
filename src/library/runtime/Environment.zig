//! An execution environment provides all needed
//! data to execute a compiled piece of code.
//! It stores its global variables, available functions
//! and available features.

const std = @import("std");
const iface = @import("interface");
const AnyPointer = @import("any-pointer").AnyPointer;
const logger = std.log.scoped(.lola);

// Import modules to reduce file size
const value_unit = @import("value.zig");
const Value = value_unit.Value;
const CompileUnit = @import("../common/CompileUnit.zig");
const vm = @import("vm.zig");
const objects = @import("objects.zig");

const String = value_unit.String;
const Array = value_unit.Array;

const ObjectPoolInterface = objects.ObjectPoolInterface;
const ObjectHandle = objects.ObjectHandle;

const Environment = @This();

allocator: std.mem.Allocator,

/// The compile unit that provides the executed script.
compileUnit: *const CompileUnit,

/// Global variables required by the script.
scriptGlobals: []Value,

/// Object interface to
objectPool: ObjectPoolInterface,

/// Stores all available global functions.
/// Functions will be contained in this unit and will be deinitialized,
/// the name must be kept alive until end of the environment.
functions: std.StringHashMap(Function),

/// This is called when the destroyObject is called.
destructor: ?*const fn (self: *Environment) void,

pub fn init(allocator: std.mem.Allocator, compileUnit: *const CompileUnit, object_pool: ObjectPoolInterface) !Environment {
    var self = Environment{
        .allocator = allocator,
        .compileUnit = compileUnit,
        .objectPool = object_pool,
        .scriptGlobals = undefined,
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
        const fun = Function{
            .script = ScriptFunction{
                .environment = null, // this is a "self-contained" script function
                .entryPoint = srcfun.entryPoint,
                .localCount = srcfun.localCount,
            },
        };
        _ = try self.functions.put(srcfun.name, fun);
    }

    return self;
}

pub fn deinit(self: *Environment) void {
    var iter = self.functions.iterator();
    while (iter.next()) |fun| {
        fun.value_ptr.deinit();
    }

    for (self.scriptGlobals) |*glob| {
        glob.deinit();
    }

    self.functions.deinit();
    self.allocator.free(self.scriptGlobals);

    self.* = undefined;
}

/// Checks if two function signatures are compatible to each other and if `Queried` can be assigned to a `Destination` type.
fn isCompatibleFunctionSignature(comptime Destination: type, comptime Queried: type) bool {
    const ti_a = @typeInfo(std.meta.Child(Destination)).@"fn";
    const ti_b = @typeInfo(std.meta.Child(Queried)).@"fn";

    if (ti_a.params.len != ti_b.params.len)
        return false;

    const rettype_a = ti_a.return_type orelse opaque {};
    const rettype_b = ti_b.return_type orelse opaque {};

    if (@typeInfo(rettype_a) == .error_union) {
        const rti_a = @typeInfo(rettype_a).error_union.payload;
        const rti_b = @typeInfo(rettype_b).error_union.payload;

        // @compileLog("Compare", rti_a, rti_b);

        if (rti_a != rti_b)
            return false;
    } else if (rettype_a != rettype_b) {
        return false;
    }

    for (ti_a.params, 0..) |arg_a, i| {
        const arg_b = ti_b.params[i];
        const type_a = arg_a.type orelse opaque {};
        const type_b = arg_b.type orelse opaque {};
        if (type_a != type_b) {
            if (@typeInfo(type_a) == .pointer) {
                const pti_a: std.builtin.Type.Pointer = @typeInfo(type_a).pointer;
                const pti_b: std.builtin.Type.Pointer = @typeInfo(type_b).pointer;
                if (pti_a.child != pti_b.child)
                    return false;
                if (pti_a.size != pti_b.size)
                    return false;
                if (pti_a.is_const and !pti_b.is_const) // if target is const, we cannot allow non-const fn
                    return false;
            } else {
                return false;
            }
        }
    }
    return true;
}

/// Installs a LoLa module.
/// Modules are containers that contain public functions with either a
/// `UserFunctionCall` or `AsyncUserFunctionCall` signature.
/// Every other function is ignored (and a debug log is generated).
pub fn installModule(self: *Environment, comptime Module: type, context: AnyPointer) !void {

    // Install all functions from the namespace "functions":
    inline for (comptime std.meta.declarations(Module)) |decl| {
        const data = @field(Module, decl.name);

        if (@typeInfo(@TypeOf(data)) == .@"fn") {
            const module_fn = @field(Module, decl.name);
            const FnType = *const @TypeOf(module_fn);

            // @compileLog("Install", decl.name, "query", FnType);

            if (comptime isCompatibleFunctionSignature(UserFunctionCall, FnType)) {
                // logger.debug("Install synchronous function {s} to environment", .{decl.name});
                try self.installFunction(decl.name, .{
                    .syncUser = UserFunction{
                        .context = context,
                        .destructor = null,
                        .call = module_fn,
                    },
                });
            } else if (comptime isCompatibleFunctionSignature(AsyncUserFunctionCall, FnType)) {
                // logger.debug("Install asynchronous function {s} to environment", .{decl.name});
                try self.installFunction(decl.name, .{
                    .asyncUser = AsyncUserFunction{
                        .context = context,
                        .destructor = null,
                        .call = module_fn,
                    },
                });
            } else {
                logger.debug("could not install {s}: unrecognized signature {s}!", .{ decl.name, @typeName(FnType) });
            }
        }
    }
}

/// Adds a function to the environment and makes it available for the script.
pub fn installFunction(self: *Environment, name: []const u8, function: Function) !void {
    const result = try self.functions.getOrPut(name);
    if (result.found_existing) {
        logger.err("tried to install already existing function '{s}'", .{name});
        return error.AlreadyExists;
    }
    result.value_ptr.* = function;
}

// Implementation to make a Environment a valid LoLa object:
pub fn getMethod(self: *Environment, name: []const u8) ?Function {
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
pub fn destroyObject(self: *Environment) void {
    if (self.destructor) |dtor| {
        dtor(self);
    }
}

/// Computes a unique signature for this environment based on
/// the size and functions stored in the environment. This is used
/// for serialization to ensure that Environments are restored into same
/// state is it was serialized from previously.
fn computeSignature(self: Environment) u64 {
    var hasher = std.hash.SipHash64(2, 4).init("Environment Seri");

    // Hash all function names to create reproducability
    {
        var iter = self.functions.iterator();
        while (iter.next()) |item| {
            hasher.update(item.key_ptr.*);
        }
    }

    // safe the length of the script globals as a bad signature for
    // the comileUnit
    {
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, self.scriptGlobals.len, .little);
        hasher.update(&buf);
    }

    return hasher.finalInt();
}

/// Serializes the environment globals in a way that these
/// are restorable later.
pub fn serialize(self: Environment, stream: anytype) !void {
    const sig = self.computeSignature();
    try stream.writeInt(u64, sig, .little);

    for (self.scriptGlobals) |glob| {
        try glob.serialize(stream);
    }
}

/// Deserializes the environment globals. This might fail with
/// `error.SignatureMismatch` when a environment with a different signature
/// is restored.
pub fn deserialize(self: *Environment, stream: anytype) !void {
    const sig_env = self.computeSignature();
    const sig_ser = try stream.readInt(u64, .little);
    if (sig_env != sig_ser)
        return error.SignatureMismatch;

    for (self.scriptGlobals) |*glob| {
        const val = try Value.deserialize(stream, self.allocator);
        glob.replaceWith(val);
    }
}

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

pub const UserFunctionCall = *const (fn (
    environment: *Environment,
    context: AnyPointer,
    args: []const Value,
) anyerror!Value);

/// A synchronous function that may be called from the script environment
pub const UserFunction = struct {
    const Self = @This();

    /// AnyPointer, will be passed to `call`.
    context: AnyPointer,

    /// Executes the function, returns a value synchronously.
    call: UserFunctionCall,

    /// Optional destructor that may free the memory stored in `context`.
    /// Is called when the function call is deinitialized.
    destructor: ?*const (fn (context: AnyPointer) void),

    pub fn deinit(self: *Self) void {
        if (self.destructor) |dtor| {
            dtor(self.context);
        }
        self.* = undefined;
    }
};

test "UserFunction (destructor)" {
    var uf1: UserFunction = .{
        .context = AnyPointer.null_pointer,
        .call = undefined,
        .destructor = null,
    };
    defer uf1.deinit();

    var uf2: UserFunction = .{
        .context = AnyPointer.make(*u32, try std.testing.allocator.create(u32)),
        .call = undefined,
        .destructor = struct {
            fn destructor(ctx: AnyPointer) void {
                std.testing.allocator.destroy(ctx.cast(*u32));
            }
        }.destructor,
    };
    defer uf2.deinit();
}

pub const AsyncUserFunctionCall = *const (fn (
    environment: *Environment,
    context: AnyPointer,
    args: []const Value,
) anyerror!AsyncFunctionCall);

/// An asynchronous function that yields execution of the VM
/// and can be resumed later.
pub const AsyncUserFunction = struct {
    const Self = @This();

    /// AnyPointer, will be passed to `call`.
    context: AnyPointer,

    /// Begins execution of this function.
    /// After the initialization, the return value will be invoked once
    /// to check if the function can finish synchronously.
    call: AsyncUserFunctionCall,

    /// Optional destructor that may free the memory stored in `context`.
    /// Is called when the function call is deinitialized.
    destructor: ?*const (fn (context: AnyPointer) void),

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
        .context = AnyPointer.make(*u32, try std.testing.allocator.create(u32)),
        .call = undefined,
        .destructor = struct {
            fn destructor(ctx: AnyPointer) void {
                std.testing.allocator.destroy(ctx.cast(*u32));
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
    context: AnyPointer,

    /// Executor that will run this function call.
    /// May return a value (function call completed) or `null` (function call still in progress).
    execute: *const fn (context: AnyPointer) anyerror!?Value,

    /// Optional destructor that may free the memory stored in `context`.
    /// Is called when the function call is deinitialized.
    destructor: ?*const fn (context: AnyPointer) void,

    pub fn deinit(self: *Self) void {
        if (self.destructor) |dtor| {
            dtor(self.context);
        }
        self.* = undefined;
    }
};

test "AsyncFunctionCall.deinit" {
    const Helper = struct {
        fn destroy(context: AnyPointer) void {
            std.testing.allocator.destroy(context.cast(*u32));
        }
        fn exec(context: AnyPointer) anyerror!?Value {
            _ = context;
            return error.NotSupported;
        }
    };

    var callWithDtor = AsyncFunctionCall{
        .object = null,
        .context = AnyPointer.make(*u32, try std.testing.allocator.create(u32)),
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

    pub fn initSimpleUser(fun: *const fn (env: *Environment, context: AnyPointer, args: []const Value) anyerror!Value) Function {
        return Self{
            .syncUser = UserFunction{
                .context = AnyPointer.null_pointer,
                .destructor = null,
                .call = fun,
            },
        };
    }

    fn convertToZigValue(comptime Target: type, value: Value) !Target {
        if (Target == Value) {
            return value;
        } else {
            const info = @typeInfo(Target);
            switch (info) {
                .Int => return try value.toInteger(Target),
                .Float => return @as(Target, @floatCast(try value.toNumber())),

                .Optional => {
                    if (value == .void)
                        return null;
                    return try convertToZigValue(std.meta.Child(Target), value);
                },

                else => return switch (Target) {
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

                    Value => unreachable,

                    else => @compileError(@typeName(Target) ++ " is not a wrappable type!"),
                },
            }
        }
    }

    fn convertToLoLaValue(allocator: std.mem.Allocator, value: anytype) !Value {
        const T = @TypeOf(value);
        const info = @typeInfo(T);
        if (info == .Int)
            return Value.initInteger(T, value);
        if (info == .Float)
            return Value.initNumber(value);
        if (info == .Optional) {
            if (value) |unwrapped|
                return try convertToLoLaValue(allocator, unwrapped);
            return .void;
        }

        if (info == .ErrorUnion) {
            return try convertToLoLaValue(allocator, try value);
        }
        if (info == .ErrorSet) {
            return value;
        }

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
        if (info != .@"fn")
            @compileError("Function.wrap expects a function!");

        const function_info = info.@"fn";
        if (function_info.is_generic)
            @compileError("Cannot wrap generic functions!");
        if (function_info.is_var_args)
            @compileError("Cannot wrap functions with variadic arguments!");

        const ArgsTuple = std.meta.ArgsTuple(F);

        const Impl = struct {
            fn invoke(env: *Environment, context: AnyPointer, args: []const Value) anyerror!Value {
                _ = context;
                if (args.len != function_info.params.len)
                    return error.InvalidArgs;

                var zig_args: ArgsTuple = undefined;

                comptime var index = 0;
                inline while (index < function_info.params.len) : (index += 1) {
                    const T = function_info.params[index].type.?;
                    const value = args[index];
                    if (T == Value) {
                        zig_args[index] = value;
                    } else {
                        zig_args[index] = try convertToZigValue(T, value);
                    }
                }

                const ReturnType = function_info.return_type.?;

                const ActualReturnType = switch (@typeInfo(ReturnType)) {
                    .ErrorUnion => |eu| eu.payload,
                    else => ReturnType,
                };

                const result: ActualReturnType = if (ReturnType != ActualReturnType)
                    try @call(.auto, function, zig_args)
                else
                    @call(.auto, function, zig_args);

                return try convertToLoLaValue(env.allocator, result);
            }
        };

        return initSimpleUser(Impl.invoke);
    }

    pub fn wrapWithAnyPointer(comptime function: anytype, context: @typeInfo(@TypeOf(function)).@"fn".args[0].type.?) Function {
        const F = @TypeOf(function);
        const FunctionAnyPointer = std.meta.Child(@TypeOf(context));
        const info = @typeInfo(F);
        if (info != .@"fn")
            @compileError("Function.wrap expects a function!");

        const function_info = info.@"fn";
        if (function_info.is_generic)
            @compileError("Cannot wrap generic functions!");
        if (function_info.is_var_args)
            @compileError("Cannot wrap functions with variadic arguments!");

        const ArgsTuple = std.meta.ArgsTuple(F);

        const Impl = struct {
            fn invoke(env: *Environment, wrapped_context: AnyPointer, args: []const Value) anyerror!Value {
                if (args.len != (function_info.args.len - 1))
                    return error.InvalidArgs;

                var zig_args: ArgsTuple = undefined;

                zig_args[0] = wrapped_context.get(FunctionAnyPointer);

                comptime var index = 1;
                inline while (index < function_info.args.len) : (index += 1) {
                    const T = function_info.args[index].type.?;
                    zig_args[index] = try convertToZigValue(T, args[index - 1]);
                }

                const ReturnType = function_info.return_type.?;

                const ActualReturnType = switch (@typeInfo(ReturnType)) {
                    .ErrorUnion => |eu| eu.payload,
                    else => ReturnType,
                };

                const result: ActualReturnType = if (ReturnType != ActualReturnType)
                    try @call(.{}, function, zig_args)
                else
                    @call(.{}, function, zig_args);

                return try convertToLoLaValue(env.allocator, result);
            }
        };

        return Self{
            .syncUser = UserFunction{
                .context = AnyPointer.init(FunctionAnyPointer, context),
                .destructor = null,
                .call = Impl.invoke,
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

    var pool = objects.ObjectPool([0]type{}).init(std.testing.allocator);
    defer pool.deinit();

    var env = try Environment.init(std.testing.allocator, &cu, pool.interface());
    defer env.deinit();

    std.debug.assert(env.scriptGlobals.len == 4);

    std.debug.assert(env.functions.count() == 3);

    const f1 = env.getMethod("fun1") orelse unreachable;
    const f2 = env.getMethod("fun_2") orelse unreachable;
    const f3 = env.getMethod("fun 3") orelse unreachable;

    try std.testing.expectEqual(@as(usize, 10), f1.script.entryPoint);
    try std.testing.expectEqual(@as(usize, 5), f1.script.localCount);
    try std.testing.expectEqual(&env, f1.script.environment.?);

    try std.testing.expectEqual(@as(usize, 21), f2.script.entryPoint);
    try std.testing.expectEqual(@as(usize, 1), f2.script.localCount);
    try std.testing.expectEqual(&env, f2.script.environment.?);

    try std.testing.expectEqual(@as(usize, 32), f3.script.entryPoint);
    try std.testing.expectEqual(@as(usize, 3), f3.script.localCount);
    try std.testing.expectEqual(&env, f3.script.environment.?);
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
            _ = value;
            unreachable;
        }
        fn takeValue(value: Value) void {
            _ = value;
            unreachable;
        }
        fn takeString(value: String) void {
            _ = value;
            unreachable;
        }
        fn takeArray(value: Array) void {
            _ = value;
            unreachable;
        }
        fn takeObjectHandle(value: ObjectHandle) void {
            _ = value;
            unreachable;
        }
        fn takeInt8(value: u8) void {
            _ = value;
            unreachable;
        }
        fn takeInt63(value: i63) void {
            _ = value;
            unreachable;
        }
        fn takeF64(value: f64) void {
            _ = value;
            unreachable;
        }
        fn takeF16(value: f16) void {
            _ = value;
            unreachable;
        }
        fn takeBool(value: bool) void {
            _ = value;
            unreachable;
        }
        fn takeStringLit(value: []const u8) void {
            _ = value;
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
            _ = a0;
            _ = a1;
            _ = a2;
            _ = a3;
            _ = a4_1;
            _ = a4_2;
            _ = a5_1;
            _ = a5_2;
            _ = a6;
            _ = a7;
            _ = a8;
            unreachable;
        }
    };

    inline for (comptime std.meta.declarations(Funcs)) |fun| {
        _ = Function.wrap(@field(Funcs, fun.name));
    }
}
