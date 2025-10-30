const std = @import("std");
const lola = @import("../main.zig");

const value_unit = @import("value.zig");
const Value = value_unit.Value;
const Decoder = @import("../common/Decoder.zig");

const ir = @import("../common/ir.zig");
const CompileUnit = @import("../common/CompileUnit.zig");
const objects = @import("objects.zig");

const Environment = @import("Environment.zig");

pub const ExecutionResult = enum {
    /// The vm instruction quota was exhausted and the execution was terminated.
    exhausted,

    /// The vm has encountered an asynchronous function call and waits for the completion.
    paused,

    /// The vm has completed execution of the program and has no more instructions to
    /// process.
    completed,
};

/// Executor of a compile unit. This virtual machine will
/// execute LoLa instructions.
pub const VM = struct {
    const Self = @This();

    const Context = struct {
        /// Stores the local variables for this call.
        locals: []Value,

        /// Provides instruction fetches for the right compile unit
        decoder: Decoder,

        /// Stores the stack balance at start of the function call.
        /// This is used to reset the stack to the right balance at the
        /// end of a function call. It is also used to check for stack underflows.
        stackBalance: usize,

        /// The script function which this context is currently executing
        environment: *Environment,
    };

    /// Describes a set of statistics for the virtual machine. Can be useful for benchmarking.
    pub const Statistics = struct {
        /// Number of instructions executed in total.
        instructions: usize = 0,

        /// Number of executions which were stalled by a asynchronous function
        stalls: usize = 0,
    };

    allocator: std.mem.Allocator,
    stack: std.ArrayList(Value),
    calls: std.ArrayList(Context),
    currentAsynCall: ?Environment.AsyncFunctionCall,
    objectPool: objects.ObjectPoolInterface,
    stats: Statistics = Statistics{},

    /// Initialize a new virtual machine that will run the given environment.
    pub fn init(allocator: std.mem.Allocator, environment: *Environment) !Self {
        var vm = Self{
            .allocator = allocator,
            .stack = std.ArrayList(Value).empty,
            .calls = std.ArrayList(Context).empty,
            .currentAsynCall = null,
            .objectPool = environment.objectPool,
        };
        errdefer vm.stack.deinit(allocator);
        errdefer vm.calls.deinit(allocator);

        try vm.stack.ensureTotalCapacity(allocator, 128);
        try vm.calls.ensureTotalCapacity(allocator, 32);

        // Initialize with special "init context" that runs the script itself
        // and hosts the global variables.
        var initFun = try vm.createContext(Environment.ScriptFunction{
            .environment = environment,
            .entryPoint = 0, // start at the very first byte
            .localCount = environment.compileUnit.temporaryCount,
        });
        errdefer vm.deinitContext(&initFun);

        try vm.calls.append(allocator, initFun);

        return vm;
    }

    pub fn deinit(self: *Self) void {
        if (self.currentAsynCall) |*asyncCall| {
            asyncCall.deinit();
        }
        for (self.stack.items) |*v| {
            v.deinit();
        }
        for (self.calls.items) |*c| {
            self.deinitContext(c);
        }
        self.stack.deinit(self.allocator);
        self.calls.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn deinitContext(self: Self, ctx: *Context) void {
        for (ctx.locals) |*v| {
            v.deinit();
        }
        self.allocator.free(ctx.locals);
        ctx.* = undefined;
    }

    /// Creates a new execution context.
    /// The script function must have a resolved environment which
    /// uses the same object pool as the main environment.
    /// It is not possible to mix several object pools.
    fn createContext(self: *Self, fun: Environment.ScriptFunction) !Context {
        std.debug.assert(fun.environment != null);
        std.debug.assert(fun.environment.?.objectPool.self == self.objectPool.self);
        var ctx = Context{
            .decoder = Decoder.init(fun.environment.?.compileUnit.code),
            .stackBalance = self.stack.items.len,
            .locals = undefined,
            .environment = fun.environment.?,
        };
        ctx.decoder.offset = fun.entryPoint;
        ctx.locals = try self.allocator.alloc(Value, fun.localCount);
        for (ctx.locals) |*local| {
            local.* = .void;
        }
        return ctx;
    }

    /// Pushes the value. Will take ownership of the pushed value.
    fn push(self: *Self, value: Value) !void {
        try self.stack.append(self.allocator, value);
    }

    /// Peeks at the top of the stack. The returned value is still owned
    /// by the stack.
    fn peek(self: Self) !*Value {
        const slice = self.stack.items;
        if (slice.len == 0)
            return error.StackImbalance;
        return &slice[slice.len - 1];
    }

    /// Pops a value from the stack. The ownership will be transferred to the caller.
    fn pop(self: *Self) !Value {
        if (self.calls.items.len > 0) {
            const ctx = &self.calls.items[self.calls.items.len - 1];

            // Assert we did not accidently have a stack underflow
            std.debug.assert(self.stack.items.len >= ctx.stackBalance);

            // this pop would produce a stack underrun for the current function call.
            if (self.stack.items.len == ctx.stackBalance)
                return error.StackImbalance;
        }

        return if (self.stack.pop()) |v| v else return error.StackImbalance;
    }

    /// Runs the virtual machine for `quota` instructions.
    pub fn execute(self: *Self, _quota: ?u32) !ExecutionResult {
        std.debug.assert(self.calls.items.len > 0);

        var quota = _quota;
        while (true) {
            if (quota) |*q| { // if we have a quota, reduce it til zero.
                if (q.* == 0)
                    return ExecutionResult.exhausted;
                q.* -= 1;
            }

            if (try self.executeSingle()) |result| {
                switch (result) {
                    .completed => {
                        // A execution may only be completed if no calls
                        // are active anymore.
                        std.debug.assert(self.calls.items.len == 0);
                        std.debug.assert(self.stack.items.len == 0);

                        return ExecutionResult.completed;
                    },
                    .yield => return ExecutionResult.paused,
                }
            }
        }
    }

    /// Executes a single instruction and returns the state of the machine.
    fn executeSingle(self: *Self) !?SingleResult {
        if (self.currentAsynCall) |*asyncCall| {
            if (asyncCall.object) |obj| {
                if (!self.objectPool.isObjectValid(obj))
                    return error.AsyncCallWithInvalidObject;
            }

            var res = try asyncCall.execute(asyncCall.context);
            if (res) |*result| {
                asyncCall.deinit();
                self.currentAsynCall = null;

                errdefer result.deinit();
                try self.push(result.*);
            } else {
                // We are not finished, continue later...
                self.stats.stalls += 1;
                return .yield;
            }
        }

        const ctx = &self.calls.items[self.calls.items.len - 1];

        const environment = ctx.environment;

        // std.debug.warn("execute 0x{X}…\n", .{ctx.decoder.offset});

        const instruction = ctx.decoder.read(ir.Instruction) catch |err| return switch (err) {
            error.EndOfStream => error.InvalidJump,
            else => error.InvalidBytecode,
        };

        self.stats.instructions += 1;

        switch (instruction) {

            // Auxiliary Section:
            .nop => {},

            .pop => {
                var value = try self.pop();
                value.deinit();
            },

            // Immediate Section:
            .push_num => |i| try self.push(Value.initNumber(i.value)),
            .push_str => |i| {
                var val = try Value.initString(self.allocator, i.value);
                errdefer val.deinit();

                try self.push(val);
            },

            .push_true => try self.push(Value.initBoolean(true)),
            .push_false => try self.push(Value.initBoolean(false)),
            .push_void => try self.push(.void),

            // Memory Access Section:

            .store_global_idx => |i| {
                if (i.value >= environment.scriptGlobals.len)
                    return error.InvalidGlobalVariable;

                const value = try self.pop();

                environment.scriptGlobals[i.value].replaceWith(value);
            },

            .load_global_idx => |i| {
                if (i.value >= environment.scriptGlobals.len)
                    return error.InvalidGlobalVariable;

                var value = try environment.scriptGlobals[i.value].clone();
                errdefer value.deinit();

                try self.push(value);
            },

            .store_local => |i| {
                if (i.value >= ctx.locals.len)
                    return error.InvalidLocalVariable;

                const value = try self.pop();

                ctx.locals[i.value].replaceWith(value);
            },

            .load_local => |i| {
                if (i.value >= ctx.locals.len)
                    return error.InvalidLocalVariable;

                var value = try ctx.locals[i.value].clone();
                errdefer value.deinit();

                try self.push(value);
            },

            // Array Operations:

            .array_pack => |i| {
                var array = try value_unit.Array.init(self.allocator, i.value);
                errdefer array.deinit();

                for (array.contents) |*item| {
                    var value = try self.pop();
                    errdefer value.deinit();

                    item.replaceWith(value);
                }

                try self.push(Value.fromArray(array));
            },

            .array_load => {
                var indexed_val = try self.pop();
                defer indexed_val.deinit();

                var index_val = try self.pop();
                defer index_val.deinit();

                const index = try index_val.toInteger(usize);

                var dupe: Value = switch (indexed_val) {
                    .array => |arr| blk: {
                        if (index >= arr.contents.len)
                            return error.IndexOutOfRange;

                        break :blk try arr.contents[index].clone();
                    },
                    .string => |str| blk: {
                        if (index >= str.contents.len)
                            return error.IndexOutOfRange;

                        break :blk Value.initInteger(u8, str.contents[index]);
                    },
                    else => return error.TypeMismatch,
                };

                errdefer dupe.deinit();

                try self.push(dupe);
            },

            .array_store => {
                var indexed_val = try self.pop();
                errdefer indexed_val.deinit();

                var index_val = try self.pop();
                defer index_val.deinit();

                if (indexed_val == .array) {
                    var value = try self.pop();
                    // only destroy value when we fail to get the array item,
                    // otherwise the value is stored in the array and must not
                    // be deinitialized after that
                    errdefer value.deinit();

                    const index = try index_val.toInteger(usize);
                    if (index >= indexed_val.array.contents.len)
                        return error.IndexOutOfRange;

                    indexed_val.array.contents[index].replaceWith(value);
                } else if (indexed_val == .string) {
                    var value = try self.pop();
                    defer value.deinit();

                    const string = &indexed_val.string;

                    const byte = try value.toInteger(u8);

                    const index = try index_val.toInteger(usize);
                    if (index >= string.contents.len)
                        return error.IndexOutOfRange;

                    if (string.refcount != null and string.refcount.?.* > 1) {
                        const new_string = try value_unit.String.init(self.allocator, string.contents);

                        string.deinit();
                        string.* = new_string;
                    }
                    std.debug.assert(string.refcount == null or string.refcount.?.* == 1);

                    const contents = try string.obtainMutableStorage();
                    contents[index] = byte;
                } else {
                    return error.TypeMismatch;
                }

                try self.push(indexed_val);
            },

            // Iterator Section:
            .iter_make => {
                var array_val = try self.pop();
                errdefer array_val.deinit();

                // is still owned by array_val and will be destroyed in case of array.
                const array = try array_val.toArray();

                try self.push(Value.fromEnumerator(value_unit.Enumerator.initFromOwned(array)));
            },

            .iter_next => {
                const enumerator_val = try self.peek();
                const enumerator = try enumerator_val.getEnumerator();
                if (enumerator.next()) |value| {
                    self.push(value) catch |err| {
                        var clone = value;
                        clone.deinit();
                        return err;
                    };
                    try self.push(Value.initBoolean(true));
                } else {
                    try self.push(Value.initBoolean(false));
                }
            },

            // Control Flow Section:

            .ret => {
                var call = self.calls.pop().?;
                defer self.deinitContext(&call);

                // Restore stack balance
                while (self.stack.items.len > call.stackBalance) {
                    var item = self.stack.pop().?;
                    item.deinit();
                }

                // No more context to execute: we have completed execution
                if (self.calls.items.len == 0)
                    return .completed;

                try self.push(.void);
            },

            .retval => {
                var value = try self.pop();
                errdefer value.deinit();

                var call = self.calls.pop().?;
                defer self.deinitContext(&call);

                // Restore stack balance
                while (self.stack.items.len > call.stackBalance) {
                    var item = self.stack.pop().?;
                    item.deinit();
                }

                // No more context to execute: we have completed execution
                if (self.calls.items.len == 0) {
                    // TODO: How to handle returns from the main scrip?
                    value.deinit();
                    return .completed;
                } else {
                    try self.push(value);
                }
            },

            .jmp => |target| {
                ctx.decoder.offset = target.value;
            },

            .jif, .jnf => |target| {
                var value = try self.pop();
                defer value.deinit();

                const boolean = try value.toBoolean();

                if (boolean == (instruction == .jnf)) {
                    ctx.decoder.offset = target.value;
                }
            },

            .call_fn => |call| {
                const method = environment.getMethod(call.function);
                if (method == null)
                    return error.FunctionNotFound;

                if (try self.executeFunctionCall(environment, call, method.?, null))
                    return .yield;
            },

            .call_obj => |call| {
                var obj_val = try self.pop();
                errdefer obj_val.deinit();
                if (obj_val != .object)
                    return error.TypeMismatch;

                const obj = obj_val.object;
                if (!self.objectPool.isObjectValid(obj))
                    return error.InvalidObject;

                const function_or_null = try self.objectPool.getMethod(obj, call.function);

                if (function_or_null) |function| {
                    if (try self.executeFunctionCall(environment, call, function, obj))
                        return .yield;
                } else {
                    return error.FunctionNotFound;
                }
            },

            // Logic Section:
            .bool_and => {
                var lhs = try self.pop();
                defer lhs.deinit();

                var rhs = try self.pop();
                defer rhs.deinit();

                const a = try lhs.toBoolean();
                const b = try rhs.toBoolean();

                try self.push(Value.initBoolean(a and b));
            },

            .bool_or => {
                var lhs = try self.pop();
                defer lhs.deinit();

                var rhs = try self.pop();
                defer rhs.deinit();

                const a = try lhs.toBoolean();
                const b = try rhs.toBoolean();

                try self.push(Value.initBoolean(a or b));
            },

            .bool_not => {
                var val = try self.pop();
                defer val.deinit();

                const a = try val.toBoolean();

                try self.push(Value.initBoolean(!a));
            },

            // Arithmetic Section:

            .negate => {
                var value = try self.pop();
                defer value.deinit();

                const num = try value.toNumber();

                try self.push(Value.initNumber(-num));
            },

            .add => {
                var rhs = try self.pop();
                defer rhs.deinit();

                var lhs = try self.pop();
                defer lhs.deinit();

                if (@as(value_unit.TypeId, lhs) != @as(value_unit.TypeId, rhs))
                    return error.TypeMismatch;

                switch (lhs) {
                    .number => {
                        try self.push(Value.initNumber(lhs.number + rhs.number));
                    },

                    .string => {
                        const lstr = lhs.string.contents;
                        const rstr = rhs.string.contents;

                        var string = try value_unit.String.initUninitialized(self.allocator, lstr.len + rstr.len);
                        errdefer string.deinit();

                        const buffer = try string.obtainMutableStorage();

                        @memcpy(buffer[0..lstr.len], lstr);
                        @memcpy(buffer[lstr.len..buffer.len], rstr);

                        try self.push(Value.fromString(string));
                    },

                    .array => {
                        const larr = lhs.array.contents;
                        const rarr = rhs.array.contents;

                        var result = try value_unit.Array.init(self.allocator, larr.len + rarr.len);
                        errdefer result.deinit();

                        for (larr, 0..) |*item, i| {
                            result.contents[i].exchangeWith(item);
                        }

                        for (rarr, 0..) |*item, i| {
                            result.contents[larr.len + i].exchangeWith(item);
                        }

                        try self.push(Value.fromArray(result));
                    },

                    else => return error.TypeMismatch,
                }
            },

            .sub => {
                try self.executeNumberArithmetic(struct {
                    fn operator(lhs: f64, rhs: f64) error{DivideByZero}!f64 {
                        return lhs - rhs;
                    }
                }.operator);
            },
            .mul => {
                try self.executeNumberArithmetic(struct {
                    fn operator(lhs: f64, rhs: f64) error{DivideByZero}!f64 {
                        return lhs * rhs;
                    }
                }.operator);
            },
            .div => {
                try self.executeNumberArithmetic(struct {
                    fn operator(lhs: f64, rhs: f64) error{DivideByZero}!f64 {
                        if (rhs == 0)
                            return error.DivideByZero;
                        return lhs / rhs;
                    }
                }.operator);
            },
            .mod => {
                try self.executeNumberArithmetic(struct {
                    fn operator(lhs: f64, rhs: f64) error{DivideByZero}!f64 {
                        if (rhs == 0)
                            return error.DivideByZero;
                        return @mod(lhs, rhs);
                    }
                }.operator);
            },

            // Comparisons:
            .eq => {
                var lhs = try self.pop();
                defer lhs.deinit();

                var rhs = try self.pop();
                defer rhs.deinit();

                try self.push(Value.initBoolean(lhs.eql(rhs)));
            },
            .neq => {
                var lhs = try self.pop();
                defer lhs.deinit();

                var rhs = try self.pop();
                defer rhs.deinit();

                try self.push(Value.initBoolean(!lhs.eql(rhs)));
            },
            .less => try self.executeCompareValues(.lt, false),
            .less_eq => try self.executeCompareValues(.lt, true),
            .greater => try self.executeCompareValues(.gt, false),
            .greater_eq => try self.executeCompareValues(.gt, true),

            // Deperecated Section:
            .scope_push,
            .scope_pop,
            .declare,
            .store_global_name,
            .load_global_name,
            => return error.DeprectedInstruction,
        }

        return null;
    }

    /// Initiates or executes a function call.
    /// Returns `true` when the VM execution should suspend after the call, else `false`.
    fn executeFunctionCall(self: *Self, environment: *Environment, call: anytype, function: Environment.Function, object: ?objects.ObjectHandle) !bool {
        return switch (function) {
            .script => |fun| blk: {
                var context = try self.createContext(fun);
                errdefer self.deinitContext(&context);

                try self.readLocals(call, context.locals);

                // Fixup stack balance after popping all locals
                context.stackBalance = self.stack.items.len;

                try self.calls.append(self.allocator, context);

                break :blk false;
            },
            .syncUser => |fun| blk: {
                const locals = try self.allocator.alloc(Value, call.argc);
                for (locals) |*l| {
                    l.* = .void;
                }
                defer {
                    for (locals) |*l| {
                        l.deinit();
                    }
                    self.allocator.free(locals);
                }

                try self.readLocals(call, locals);

                var result = try fun.call(environment, fun.context, locals);
                errdefer result.deinit();

                try self.push(result);

                break :blk false;
            },
            .asyncUser => |fun| blk: {
                const locals = try self.allocator.alloc(Value, call.argc);
                for (locals) |*l| {
                    l.* = .void;
                }
                defer {
                    for (locals) |*l| {
                        l.deinit();
                    }
                    self.allocator.free(locals);
                }

                try self.readLocals(call, locals);

                self.currentAsynCall = try fun.call(environment, fun.context, locals);
                self.currentAsynCall.?.object = object;

                break :blk true;
            },
        };
    }

    /// Reads a number of call arguments into a slice.
    /// If an error happens, all items in `locals` are valid and must be deinitialized.
    fn readLocals(self: *Self, call: ir.Instruction.CallArg, locals: []Value) !void {
        var i: usize = 0;
        while (i < call.argc) : (i += 1) {
            var value = try self.pop();
            if (i < locals.len) {
                locals[i].replaceWith(value);
            } else {
                value.deinit(); // Discard the value
            }
        }
    }

    fn executeCompareValues(self: *Self, wantedOrder: std.math.Order, allowEql: bool) !void {
        var rhs = try self.pop();
        defer rhs.deinit();

        var lhs = try self.pop();
        defer lhs.deinit();

        if (@as(value_unit.TypeId, lhs) != @as(value_unit.TypeId, rhs))
            return error.TypeMismatch;

        const order = switch (lhs) {
            .number => |num| std.math.order(num, rhs.number),
            .string => |str| std.mem.order(u8, str.contents, rhs.string.contents),
            else => return error.InvalidOperator,
        };

        try self.push(Value.initBoolean(
            if (order == .eq and allowEql) true else order == wantedOrder,
        ));
    }

    const SingleResult = enum {
        /// The program has encountered an asynchronous function
        completed,

        /// execution and waits for completion.
        yield,
    };

    fn executeNumberArithmetic(self: *Self, operator: *const fn (f64, f64) error{DivideByZero}!f64) !void {
        var rhs = try self.pop();
        defer rhs.deinit();

        var lhs = try self.pop();
        defer lhs.deinit();

        const n_lhs = try lhs.toNumber();
        const n_rhs = try rhs.toNumber();

        const result = try operator(n_lhs, n_rhs);

        try self.push(Value.initNumber(result));
    }

    pub const StackTraceItem = struct {
        location: ?CompileUnit.DebugSymbol,
        function: []const u8,
        compile_unit: *const CompileUnit,
    };

    pub fn getStackTop(self: Self) ?StackTraceItem {
        if (self.calls.items.len == 0)
            return null;
        const call = self.calls.items[self.calls.items.len - 1];

        const stack_compile_unit = call.environment.compileUnit;

        var item = StackTraceItem{
            .compile_unit = stack_compile_unit,
            .location = stack_compile_unit.lookUp(call.decoder.offset),
            .function = "<main>",
        };

        for (stack_compile_unit.functions) |fun| {
            if (call.decoder.offset < fun.entryPoint)
                break;
            item.function = fun.name;
        }

        return item;
    }

    /// Prints a stack trace for the current code position into `stream`.
    pub fn printStackTrace(self: Self, stream: *std.Io.Writer) !void {
        var i: usize = self.calls.items.len;
        while (i > 0) {
            i -= 1;
            const call = self.calls.items[i];

            const stack_compile_unit = call.environment.compileUnit;

            const location = stack_compile_unit.lookUp(call.decoder.offset);

            var current_fun: []const u8 = "<main>";
            for (stack_compile_unit.functions) |fun| {
                if (call.decoder.offset < fun.entryPoint)
                    break;
                current_fun = fun.name;
            }

            try stream.print("[{d}] at offset {d} ({s}:{d}:{d}) in function {s}\n", .{
                i,
                call.decoder.offset,
                stack_compile_unit.comment,
                if (location) |l| l.sourceLine else 0,
                if (location) |l| l.sourceColumn else 0,
                current_fun,
            });
        }
    }

    pub fn serialize(self: Self, envmap: *lola.runtime.EnvironmentMap, stream: anytype) !void {
        if (self.currentAsynCall != null)
            return error.NotSupportedYet; // we cannot serialize async function that are in-flight atm

        try stream.writeInt(u64, self.stack.items.len, .little);
        try stream.writeInt(u64, self.calls.items.len, .little);

        for (self.stack.items) |item| {
            try item.serialize(stream);
        }

        for (self.calls.items) |item| {
            try stream.writeInt(u16, @as(u16, @intCast(item.locals.len)), .little);
            try stream.writeInt(u32, item.decoder.offset, .little); // we don't need to store the CompileUnit of the decoder, as it is implicitly referenced by the environment
            try stream.writeInt(u32, @as(u32, @intCast(item.stackBalance)), .little);
            if (envmap.queryByPtr(item.environment)) |env_id| {
                try stream.writeInt(u32, env_id, .little);
            } else {
                return error.UnregisteredEnvironmentPointer;
            }
            for (item.locals) |loc| {
                try loc.serialize(stream);
            }
        }
    }

    pub fn deserialize(allocator: std.mem.Allocator, envmap: *lola.runtime.EnvironmentMap, stream: anytype) !Self {
        const stack_size = try stream.readInt(u64, .little);
        const call_size = try stream.readInt(u64, .little);

        var vm = Self{
            .allocator = allocator,
            .stack = std.ArrayList(Value).empty,
            .calls = std.ArrayList(Context).empty,
            .currentAsynCall = null,
            .objectPool = undefined,
        };
        errdefer vm.stack.deinit();
        errdefer vm.calls.deinit();

        try vm.stack.ensureTotalCapacity(allocator, @min(stack_size, 128));
        try vm.calls.ensureTotalCapacity(allocator, @min(call_size, 32));

        try vm.stack.resize(stack_size);
        for (vm.stack.items) |*item| {
            item.* = .void;
        }
        errdefer for (vm.stack.items) |*item| {
            item.deinit();
        };
        for (vm.stack.items) |*item| {
            item.* = try Value.deserialize(stream, allocator);
        }

        {
            var i: usize = 0;
            while (i < call_size) : (i += 1) {
                const local_count = try stream.readInt(u16, .little);
                const offset = try stream.readInt(u32, .little);
                const stack_balance = try stream.readInt(u32, .little);
                const env_id = try stream.readInt(u32, .little);

                const env = envmap.queryById(env_id) orelse return error.UnregisteredEnvironmentPointer;

                if (i == 0) {
                    // first call defines which environment we use for our
                    // object pool reference:
                    vm.objectPool = env.objectPool;
                }

                var ctx = try vm.createContext(Environment.ScriptFunction{
                    .environment = env,
                    .entryPoint = offset,
                    .localCount = local_count,
                });
                ctx.stackBalance = stack_balance;
                errdefer vm.deinitContext(&ctx);

                for (ctx.locals) |*local| {
                    local.* = try Value.deserialize(stream, allocator);
                }

                try vm.calls.append(allocator, ctx);
            }
        }

        return vm;
    }
};

const TestPool = objects.ObjectPool(.{});

fn runTest(comptime TestRunner: type) !void {
    var code = TestRunner.code;

    const cu = CompileUnit{
        .arena = undefined,
        .comment = "",
        .globalCount = 0,
        .temporaryCount = 0,
        .functions = &[_]CompileUnit.Function{},
        .debugSymbols = &[0]CompileUnit.DebugSymbol{},
        .code = &code,
    };

    var pool = TestPool.init(std.testing.allocator);
    defer pool.deinit();

    var env = try Environment.init(std.testing.allocator, &cu, pool.interface());
    defer env.deinit();

    var vm = try VM.init(std.testing.allocator, &env);
    defer vm.deinit();

    try TestRunner.verify(&vm);
}

test "VM basic execution" {
    try runTest(struct {
        var code = [_]u8{
            @intFromEnum(ir.InstructionName.ret),
        };

        fn verify(vm: *VM) !void {
            const result = try vm.execute(1);

            try std.testing.expectEqual(ExecutionResult.completed, result);
        }
    });
}

test "VM endless loop exhaustion" {
    try runTest(struct {
        var code = [_]u8{
            @intFromEnum(ir.InstructionName.jmp),
            0x00,
            0x00,
            0x00,
            0x00,
        };

        fn verify(vm: *VM) !void {
            const result = try vm.execute(1000);
            try std.testing.expectEqual(ExecutionResult.exhausted, result);
        }
    });
}

test "VM invalid code panic" {
    try runTest(struct {
        var code = [_]u8{
            @intFromEnum(ir.InstructionName.jmp),
            0x00,
            0x00,
            0x00,
        };

        fn verify(vm: *VM) !void {
            try std.testing.expectError(error.InvalidBytecode, vm.execute(1000));
        }
    });
}

test "VM invalid jump panic" {
    try runTest(struct {
        var code = [_]u8{
            @intFromEnum(ir.InstructionName.jmp),
            0x00,
            0x00,
            0x00,
            0xFF,
        };

        fn verify(vm: *VM) !void {
            try std.testing.expectError(error.InvalidJump, vm.execute(1000));
        }
    });
}
