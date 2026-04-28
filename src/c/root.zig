const lola = @import("lola");
const std = @import("std");

const Environment = lola.runtime.Environment;
const Value = lola.runtime.Value;
const Context = lola.runtime.Context;
const CompileUnit = lola.CompileUnit;
const VM = lola.runtime.VM;
const Diagnostics = lola.compiler.Diagnostics;
const AsyncFunctionCall = lola.runtime.AsyncFunctionCall;
const span = std.mem.span;

// This is our global object pool that is back-referenced
// by the runtime library.
pub const ObjectPool = lola.runtime.objects.ObjectPool([_]type{
    lola.libs.runtime.LoLaList,
    lola.libs.runtime.LoLaDictionary,
    CObject,
});

// uncomment this to check for leaks
var gpa = std.heap.DebugAllocator(.{}).init;
const alloc = gpa.allocator();
export fn lola_alloc_deinit() void {
    _ = gpa.deinit();
}
// const alloc = std.heap.c_allocator;

var static_error: ?anyerror = null;

export fn lola_getErrorName() [*:0]const u8 {
    if (static_error) |err| {
        return @errorName(err);
    } else {
        return "Success";
    }
}
export fn lola_hasError() bool {
    return static_error != null;
}

export fn lola_alloc_alloc(size: usize, alignment: usize) ?[*]u8 {
    return alloc.rawAlloc(
        size,
        std.mem.Alignment.fromByteUnits(alignment),
        @returnAddress(),
    );
}
export fn lola_alloc_free(in_ptr: ?[*]u8, size: usize, alignment: usize) void {
    alloc.rawFree(in_ptr.?[0..size], std.mem.Alignment.fromByteUnits(alignment), @returnAddress());
}

export fn lola_alloc_resize(
    out_ptr: ?*?[*]u8,
    old_size: usize,
    new_size: usize,
    alignment: usize,
) Result {
    const slice: []u8 = out_ptr.?.*.?[0..old_size];
    if (alloc.rawRemap(slice, std.mem.Alignment.fromByteUnits(alignment), new_size, @returnAddress())) |new_alloc| {
        out_ptr.?.* = new_alloc;
        return .success;
    } else {
        const new_ptr = if (lola_alloc_alloc(new_size, alignment)) |ptr|
            ptr
        else
            return .out_of_memory;
        const new_slice = new_ptr[0..new_size];
        @memcpy(new_slice, slice);
        lola_alloc_free(slice.ptr, old_size, alignment);
        return .success;
    }
}

const Result = enum(u8) {
    success = 0,
    generic_error = 1,
    out_of_memory = 2,
    write_failed = 3,
    invalid_format = 4,
    unsupported_version = 5,
    corrupted_data = 6,
    already_exists = 7,
    async_call_with_invalid_object = 8,
    invalid_jump = 9,
    invalid_bytecode = 10,
    invalid_global_variable = 11,
    invalid_local_variable = 12,
    invalid_field = 13,
    index_out_of_range = 14,
    type_mismatch = 15,
    function_not_found = 16,
    invalid_object = 17,
    divide_by_zero = 18,
    deprecated_instruction = 19,
    invalid_operator = 20,

    fn fromError(err: anyerror) Result {
        return switch (err) {
            error.OutOfMemory => .out_of_memory,
            error.WriteFailed => .write_failed,
            error.InvalidFormat => .invalid_format,
            error.UnsupportedVersion => .unsupported_version,
            error.CorruptedData => .corrupted_data,
            error.AlreadyExists => .already_exists,
            error.AsyncCallWithInvalidObject => .async_call_with_invalid_object,
            error.InvalidJump => .invalid_jump,
            error.InvalidBytecode => .invalid_bytecode,
            error.InvalidGlobalVariable => .invalid_global_variable,
            error.InvalidLocalVariable => .invalid_local_variable,
            error.InvalidField => .invalid_field,
            error.IndexOutOfRange => .index_out_of_range,
            error.TypeMismatch => .type_mismatch,
            error.FunctionNotFound => .function_not_found,
            error.InvalidObject => .invalid_object,
            error.DivideByZero => .divide_by_zero,
            error.DeprectedInstruction => .deprecated_instruction,
            error.InvalidOperator => .invalid_operator,
            else => .generic_error,
        };
    }
};

const Str = extern struct {
    items: [*]const u8,
    len: usize,
    allocated: bool = false,
    fn fromSlice(slice: []const u8) Str {
        return Str{ .items = slice.ptr, .len = slice.len };
    }
    fn fromAllocSlice(slice: []const u8) Str {
        return Str{ .items = slice.ptr, .len = slice.len, .allocated = true };
    }
    export fn lola_Str_fromC(str: [*:0]const u8) Str {
        const slice = span(str);
        return fromSlice(slice);
    }
    export fn lola_Str_deinit(str: Str) void {
        if (str.allocated)
            alloc.free(str.toSlice());
    }
    fn toSlice(self: Str) []const u8 {
        return self.items[0..self.len];
    }
};

export fn lola_Diagnostics_deinit(cdiag: ?*Diagnostics) void {
    if (cdiag) |diag| {
        diag.deinit();
        alloc.destroy(diag);
    }
}
export fn lola_Diagnostics_display(diag: ?*Diagnostics) Result {
    var stdout = std.fs.File.stdout().writer(&.{});
    for (diag.?.messages.items) |message| {
        stdout.interface.print("{f}\n", .{message}) catch |e| {
            static_error = e;
            return Result.fromError(e);
        };
    }
    return .success;
}
export fn lola_Diagnostics_hasErrors(diag: ?*Diagnostics) bool {
    return diag.?.hasErrors();
}
const CAsyncFunctionCall = extern struct {
    user_data: ?*anyopaque = null,
    /// returns false on error, or true on success
    execute: *const fn (user_data: ?*anyopaque, return_value: *Value, is_return_value_set: *bool) callconv(.c) bool,
    destructor: Destoructor = null,
};
const FuncType = extern struct {
    func_type: CallbackType,
    func: extern union {
        sync: SyncUserFunc,
        async: AsyncUserFunc,
    },
    const CallbackType = enum(u8) {
        sync,
        async,
    };
    const SyncUserFunc = *const fn (environment: *Environment, user_data: ?*anyopaque, args: [*]const Value, args_len: usize, return_value: *Value) callconv(.c) bool;
    const AsyncUserFunc = *const fn (environment: *Environment, user_data: ?*anyopaque, args: [*]const Value, args_len: usize, return_value: *CAsyncFunctionCall) callconv(.c) bool;
};
const Destoructor = ?*const fn (user_data: ?*anyopaque) callconv(.c) void;
pub const CObject = extern struct {
    const Self = @This();
    const VTable = extern struct {
        getMethod: *const fn (user_data: ?*anyopaque, name: Str, func: *FuncType) callconv(.c) bool,
        destroyObject: Destoructor,
    };

    user_data: ?*anyopaque,
    vtable: VTable,

    fn init(user_data: ?*anyopaque, vtable: VTable) Self {
        return Self{
            .user_data = user_data,
            .vtable = vtable,
        };
    }

    export fn lola_Object_init(user_data: ?*anyopaque, vtable: VTable) ?*Self {
        const allocation = alloc.create(Self) catch |e| {
            static_error = e;
            return null;
        };
        allocation.* = .init(user_data, vtable);
        return allocation;
    }

    pub fn getMethod(self: *Self, name: []const u8) ?lola.runtime.Function {
        var func = FuncType{
            .func_type = .sync,
            .func = undefined,
        };
        if (self.vtable.getMethod(self.user_data, .fromSlice(name), &func)) {
            const c_user_data = alloc.create(CallbackData) catch |e| {
                static_error = e;
                return null;
            };
            c_user_data.* = CallbackData{
                .c_func = func,
                .user_data = self.user_data,
            };
            return switch (func.func_type) {
                .sync => lola.runtime.Function{ .syncUser = .{
                    .context = .make(*CallbackData, c_user_data),
                    .call = CallbackData.call,
                    .destructor = CallbackData.destructor,
                } },
                .async => lola.runtime.Function{ .asyncUser = .{
                    .context = .make(*CallbackData, c_user_data),
                    .call = CallbackData.callAsync,
                    .destructor = CallbackData.destructor,
                } },
            };
        } else {
            return null;
        }
    }

    pub fn destroyObject(self: *Self) void {
        if (self.vtable.destroyObject) |destory| {
            destory(self.user_data);
        }
        alloc.destroy(self);
    }

    // TODO
    // pub fn serializeObject(writer: *std.Io.Writer, object: *Self) !void {}

    // TODO
    // pub fn deserializeObject(allocator: std.mem.Allocator, reader: *std.Io.Reader) !*Self {}
};

const CArray = extern struct {
    elements: [*]Value,
    len: usize,
};
const CEnumerator = extern struct {
    array: CArray,
    index: usize,
};
const CValue = extern struct {
    value_type: lola.runtime.value.TypeId,
    value: extern union {
        // non-allocating
        void: void,
        number: f64,
        object: lola.runtime.objects.ObjectHandle,
        boolean: bool,

        // allocating
        string: Str,
        array: CArray,
        enumerator: CEnumerator,
        @"struct": void,
    },
    fn get(value: Value) CValue {
        return .{ .value_type = std.meta.activeTag(value), .value = switch (value) {
            .void => .{ .void = void{} },
            .number => |number| .{ .number = number },
            .object => |object| .{ .object = object },
            .boolean => |boolean| .{ .boolean = boolean },
            .string => |string| .{ .string = Str{ .items = string.contents.ptr, .len = string.contents.len } },
            .array => |array| .{ .array = CArray{ .elements = array.contents.ptr, .len = array.contents.len } },
            .enumerator => |enumerator| .{ .enumerator = CEnumerator{
                .index = enumerator.index,
                .array = .{ .elements = enumerator.array.contents.ptr, .len = enumerator.array.contents.len },
            } },
            .@"struct" => .{ .@"struct" = void{} },
        } };
    }
    fn to(self: CValue) Value {
        return switch (self.value_type) {
            .void => .void,
            .number => Value.initNumber(self.value.number),
            .object => Value.initObject(self.value.object),
            .boolean => Value.initBoolean(self.value.boolean),
            .string => Value{ .string = .initFromOwned(alloc, self.value.string.items[0..self.value.string.len]) },
            .array => Value.fromArray(.{ .allocator = alloc, .contents = self.value.array.elements[0..self.value.array.len] }),
            .enumerator => Value{ .enumerator = .{
                .index = self.value.enumerator.index,
                .array = .{
                    .allocator = alloc,
                    .contents = self.value.enumerator.array.elements[0..self.value.enumerator.array.len],
                },
            } },
            .@"struct" => Value.void,
        };
    }
};
export fn lola_CArray_init(value: ?*CArray, size: usize) Result {
    const array = lola.runtime.value.Array.init(alloc, size) catch |e| {
        static_error = e;
        return Result.fromError(e);
    };
    const contents = array.contents;
    value.?.* = .{ .elements = contents.ptr, .len = contents.len };
    return .success;
}
export fn lola_CValue_toValue(value: CValue, out_value: ?*Value) void {
    out_value.?.* = value.to();
}
export fn lola_CValue_fromValue(value: ?*const Value) CValue {
    return CValue.get(value.?.*);
}

export fn lola_Value_initObject(env: ?*Environment, user_object: ?*CObject, value: ?*Value) Result {
    value.?.deinit();
    value.?.* = Value.initObject(env.?.objectPool.castTo(ObjectPool).createObject(user_object.?) catch |e| {
        static_error = e;
        return Result.fromError(e);
    });
    return .success;
}
export fn lola_Value_initString(string: Str, value: ?*Value) Result {
    value.?.deinit();
    value.?.* = Value.initString(alloc, string.items[0..string.len]) catch |e| {
        static_error = e;
        return Result.fromError(e);
    };
    return .success;
}
export fn lola_Value_initBoolean(boolean: bool, value: ?*Value) void {
    value.?.deinit();
    value.?.* = Value.initBoolean(boolean);
}
export fn lola_Value_initNumber(number: f64, value: ?*Value) void {
    value.?.deinit();
    value.?.* = Value.initNumber(number);
}
/// Only call this on Values you own
export fn lola_Value_deinit(value: ?*Value) void {
    value.?.deinit();
    alloc.destroy(value.?);
}
export fn lola_Value_clone(value: ?*const Value) ?*Value {
    const allocation = alloc.create(Value) catch |e| {
        static_error = e;
        return null;
    };
    allocation.* = value.?.clone() catch |e| {
        static_error = e;
        return null;
    };
    return allocation;
}
export fn lola_Value_sizeof() usize {
    return @sizeOf(Value);
}

export fn lola_indexArgs(args: ?[*]const Value, arg_len: usize, index: usize) *const Value {
    return &args.?[0..arg_len][index];
}

export fn lola_compile(cdiag: ?*?*Diagnostics, cchunk_name: Str, csource_code: Str) ?*CompileUnit {
    const diag = if (cdiag.?.*) |diag_ptr| diag_ptr else diag: {
        const diag = alloc.create(Diagnostics) catch |e| {
            static_error = e;
            return null;
        };
        diag.* = lola.compiler.Diagnostics.init(alloc);
        cdiag.?.* = diag;
        break :diag diag;
    };
    const maybe_cu = lola.compiler.compile(alloc, diag, cchunk_name.toSlice(), csource_code.toSlice()) catch |e| {
        static_error = e;
        diag.deinit();
        return null;
    };

    if (maybe_cu) |cu| {
        const cu_alloc = alloc.create(CompileUnit) catch |e| {
            static_error = e;
            diag.deinit();
            return null;
        };
        cu_alloc.* = cu;
        return cu_alloc;
    } else {
        diag.deinit();
        return null;
    }
}
export fn lola_CompileUnit_deinit(cu: ?*CompileUnit) void {
    cu.?.deinit();
    alloc.destroy(cu.?);
}

export fn lola_ObjectPool_init() ?*ObjectPool {
    const allocation = alloc.create(ObjectPool) catch |e| {
        static_error = e;
        return null;
    };
    allocation.* = ObjectPool.init(alloc);
    return allocation;
}
export fn lola_ObjectPool_deinit(cobject_pool: ?*ObjectPool) void {
    if (cobject_pool) |object_pool| {
        object_pool.deinit();
        alloc.destroy(object_pool);
    }
}

export fn lola_Environment_init(compile_unit: ?*CompileUnit, object_pool: ?*ObjectPool) ?*Environment {
    const allocation = alloc.create(Environment) catch |e| {
        static_error = e;
        return null;
    };
    allocation.* = Environment.init(alloc, compile_unit.?, object_pool.?.interface()) catch |e| {
        static_error = e;
        return null;
    };
    return allocation;
}
export fn lola_Environment_deinit(cenvironment: ?*Environment) void {
    if (cenvironment) |environment| {
        environment.deinit();
        alloc.destroy(environment);
    }
}

const CallbackData = extern struct {
    user_data: ?*anyopaque,
    c_func: FuncType,
    destructor_func: Destoructor = null,

    fn call(env: *Environment, context: Context, args: []const Value) anyerror!Value {
        const ud: *CallbackData = context.cast(*CallbackData);
        var result: Value = .void;
        return if (ud.c_func.func.sync(env, ud.user_data, args.ptr, args.len, &result)) result else error.CLolaFuncError;
    }
    fn callAsync(env: *Environment, context: Context, args: []const Value) anyerror!AsyncFunctionCall {
        const ud: *CallbackData = context.cast(*CallbackData);
        var result: CAsyncFunctionCall = .{ .execute = undefined };
        if (ud.c_func.func.async(env, ud.user_data, args.ptr, args.len, &result)) {
            const func_call = try alloc.create(CAsyncFunctionCall);
            func_call.* = result;
            return AsyncFunctionCall{
                .context = .make(*CAsyncFunctionCall, func_call),
                .execute = struct {
                    fn execute(cont: Context) anyerror!?Value {
                        const async_call: *CAsyncFunctionCall = cont.cast(*CAsyncFunctionCall);
                        var return_value: Value = .void;
                        var is_return_value_set: bool = false;
                        if (!async_call.execute(async_call.user_data, &return_value, &is_return_value_set)) {
                            return error.CLolaFuncError;
                        } else {
                            return if (is_return_value_set) return_value else null;
                        }
                    }
                }.execute,
                .destructor = struct {
                    fn destructor(cont: Context) void {
                        const async_call: *CAsyncFunctionCall = cont.cast(*CAsyncFunctionCall);
                        if (async_call.destructor) |dest| dest(async_call.user_data);
                        alloc.destroy(async_call);
                    }
                }.destructor,
            };
        } else {
            return error.CLolaFuncError;
        }
    }
    fn destructor(context: Context) void {
        const ud: *CallbackData = context.cast(*CallbackData);
        if (ud.destructor_func) |destructor_func| destructor_func(ud.user_data);
        alloc.destroy(ud);
    }
};
export fn lola_Environment_install(environment: ?*Environment, name: Str, ud: CallbackData) Result {
    const c_user_data = alloc.create(CallbackData) catch |e| {
        static_error = e;
        return Result.fromError(e);
    };
    c_user_data.* = ud;
    switch (ud.c_func.func_type) {
        .sync => {
            environment.?.installFunction(name.toSlice(), .{ .syncUser = .{
                .call = CallbackData.call,
                .context = .make(*CallbackData, c_user_data),
                .destructor = CallbackData.destructor,
            } }) catch |e| {
                static_error = e;
                return Result.fromError(e);
            };
            return .success;
        },
        .async => {
            environment.?.installFunction(name.toSlice(), .{ .asyncUser = .{
                .call = CallbackData.callAsync,
                .context = .make(*CallbackData, c_user_data),
                .destructor = CallbackData.destructor,
            } }) catch |e| {
                static_error = e;
                return Result.fromError(e);
            };
            return .success;
        },
    }
}

export fn lola_Environment_installStd(env: ?*Environment) Result {
    env.?.installModule(lola.libs.std, .null_pointer) catch |e| {
        static_error = e;
        return Result.fromError(e);
    };
    return .success;
}
export fn lola_Environment_installRuntime(env: ?*Environment) Result {
    env.?.installModule(lola.libs.runtime, .null_pointer) catch |e| {
        static_error = e;
        return Result.fromError(e);
    };
    return .success;
}

export fn lola_VM_init(environment: ?*Environment) ?*VM {
    const allocation = alloc.create(VM) catch |e| {
        static_error = e;
        return null;
    };
    allocation.* = VM.init(alloc, environment.?) catch |e| {
        static_error = e;
        return null;
    };
    return allocation;
}
export fn lola_VM_deinit(cvm: ?*VM) void {
    if (cvm) |vm| {
        vm.deinit();
        alloc.destroy(vm);
    }
}
export fn lola_VM_execute(vm: ?*VM, quota: u32, result_ptr: *lola.runtime.ExecutionResult) Result {
    result_ptr.* = vm.?.execute(if (quota == 0) null else quota) catch |e| {
        static_error = e;
        return Result.fromError(e);
    };
    return .success;
}

export fn lola_loadCUFromMem(mem: ?[*]u8, len: usize) ?*CompileUnit {
    var reader = std.Io.Reader.fixed(mem.?[0..len]);
    const ptr = alloc.create(CompileUnit) catch |e| {
        static_error = e;
        return null;
    };
    errdefer alloc.destroy(ptr);
    ptr.* = CompileUnit.loadFromStream(alloc, &reader) catch |e| {
        static_error = e;
        return null;
    };
    return ptr;
}

const CDisassemblerOptions = extern struct {
    /// Prefix each line of the disassembly with the hexadecimal address.
    addressPrefix: bool,

    /// If set, a hexdump with both hex- and ascii display will be emitted.
    /// Each line of text will contain `hexwidth` number of bytes.
    hexwidth: usize,

    /// If set to `true`, the output will contain a line with the
    /// name of function that starts at this offset. This option
    /// is set by default.
    labelOutput: bool,

    /// If set to `true`, the disassembled instruction will be emitted.
    /// This is set by default.
    instructionOutput: bool,
};
const DisassemblerOptions = lola.dis.DisassemblerOptions;
export fn lola_dis_toBuffer(ptr: ?[*]u8, len: usize, cu: ?*const CompileUnit, options: CDisassemblerOptions) Result {
    var w = std.Io.Writer.fixed(ptr.?[0..len]);
    lola.dis.disassemble(&w, cu.?.*, .{
        .addressPrefix = options.addressPrefix,
        .hexwidth = if (options.hexwidth > 0) options.hexwidth else null,
        .instructionOutput = options.instructionOutput,
        .labelOutput = options.labelOutput,
    }) catch |e| {
        static_error = e;
        return Result.fromError(e);
    };
    return .success;
}
export fn lola_dis_alloc(cu: ?*const CompileUnit, options: CDisassemblerOptions, dis: ?*Str) Result {
    var w = std.Io.Writer.Allocating.init(alloc);
    lola.dis.disassemble(&w.writer, cu.?.*, .{
        .addressPrefix = options.addressPrefix,
        .hexwidth = if (options.hexwidth > 0) options.hexwidth else null,
        .instructionOutput = options.instructionOutput,
        .labelOutput = options.labelOutput,
    }) catch |e| {
        static_error = e;
        w.deinit();
        return Result.fromError(e);
    };
    const slice = w.toOwnedSlice() catch |e| {
        static_error = e;
        w.deinit();
        return Result.fromError(e);
    };
    dis.?.* = Str.fromAllocSlice(slice);
    return .success;
}
export fn lola_dis_allocZ(cu: ?*const CompileUnit, options: CDisassemblerOptions, dis: ?*Str) Result {
    var w = std.Io.Writer.Allocating.init(alloc);
    lola.dis.disassemble(&w.writer, cu.?.*, .{
        .addressPrefix = options.addressPrefix,
        .hexwidth = if (options.hexwidth > 0) options.hexwidth else null,
        .instructionOutput = options.instructionOutput,
        .labelOutput = options.labelOutput,
    }) catch |e| {
        static_error = e;
        w.deinit();
        return Result.fromError(e);
    };
    const slice = w.toOwnedSliceSentinel(0) catch |e| {
        static_error = e;
        w.deinit();
        return Result.fromError(e);
    };
    dis.?.* = Str.fromAllocSlice(slice[0 .. slice.len + 1]);
    return .success;
}
