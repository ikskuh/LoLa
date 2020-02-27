const std = @import("std");
usingnamespace @import("value.zig");
usingnamespace @import("ir.zig");
usingnamespace @import("compile_unit.zig");
usingnamespace @import("decoder.zig");
usingnamespace @import("named_global.zig");
usingnamespace @import("environment.zig");

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
    };

    allocator: *std.mem.Allocator,
    environment: *const Environment,
    stack: std.ArrayList(Value),
    calls: std.ArrayList(Context),
    currentAsynCall: ?AsyncFunctionCall,

    /// Initialize a new virtual machine that will run the given environment.
    pub fn init(allocator: *std.mem.Allocator, environment: *const Environment) !Self {
        var vm = Self{
            .allocator = allocator,
            .environment = environment,
            .stack = std.ArrayList(Value).init(allocator),
            .calls = std.ArrayList(Context).init(allocator),
            .currentAsynCall = null,
        };
        errdefer vm.stack.deinit();
        errdefer vm.calls.deinit();

        // Initialize with special "init context" that runs the script itself
        // and hosts the global variables.
        const initFun = try vm.createContext(ScriptFunction{
            .compileUnit = environment.compileUnit,
            .entryPoint = 0, // start at the very first byte
            .localCount = environment.compileUnit.temporaryCount,
        });
        errdefer vm.deinitContext(initFun);

        try vm.calls.append(initFun);

        return vm;
    }

    pub fn deinit(self: Self) void {
        if (self.currentAsynCall) |asyncCall| {
            asyncCall.deinit();
        }
        for (self.stack.toSliceConst()) |v| {
            v.deinit();
        }
        for (self.calls.toSliceConst()) |c| {
            deinitContext(self, c);
        }
        self.stack.deinit();
        self.calls.deinit();
    }

    fn deinitContext(self: Self, ctx: Context) void {
        for (ctx.locals) |v| {
            v.deinit();
        }
        self.allocator.free(ctx.locals);
    }

    /// Creates a new execution context.
    fn createContext(self: *Self, fun: ScriptFunction) !Context {
        var ctx = Context{
            .decoder = Decoder.init(fun.compileUnit.code),
            .stackBalance = self.stack.len,
            .locals = undefined,
        };
        ctx.decoder.offset = fun.entryPoint;
        ctx.locals = try self.allocator.alloc(Value, fun.localCount);
        for (ctx.locals) |*local| {
            local.* = Value.initVoid();
        }
        return ctx;
    }

    /// Pushes the value. Will take ownership of the pushed value.
    fn push(self: *Self, value: Value) !void {
        try self.stack.append(value);
    }

    /// Peeks at the top of the stack. The returned value is still owned
    /// by the stack.
    fn peek(self: Self) !*Value {
        const slice = self.stack.toSlice();
        if (slice.len == 0)
            return error.StackImbalance;
        return &slice[slice.len - 1];
    }

    /// Pops a value from the stack. The ownership will be transferred to the caller.
    fn pop(self: *Self) !Value {
        if (self.calls.len > 0) {
            const ctx = &self.calls.toSlice()[self.calls.len - 1];

            // Assert we did not accidently have a stack underflow
            std.debug.assert(self.stack.len >= ctx.stackBalance);

            // this pop would produce a stack underrun for the current function call.
            if (self.stack.len == ctx.stackBalance)
                return error.StackImbalance;
        }

        return if (self.stack.popOrNull()) |v| v else return error.StackImbalance;
    }

    /// Runs the virtual machine for `quota` instructions.
    pub fn execute(self: *Self, _quota: ?u32) !ExecutionResult {
        std.debug.assert(self.calls.len > 0);

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
                        std.debug.assert(self.calls.len == 0);
                        std.debug.assert(self.stack.len == 0);

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
            const res = try asyncCall.execute(asyncCall.context);
            if (res) |result| {
                asyncCall.deinit();
                self.currentAsynCall = null;

                errdefer result.deinit();
                try self.push(result);
            } else {
                // We are not finished, continue later...
                return .yield;
            }
        }

        const ctx = &self.calls.toSlice()[self.calls.len - 1];

        std.debug.warn("execute 0x{X}…\n", .{ctx.decoder.offset});

        const instruction = try ctx.decoder.read(Instruction);
        switch (instruction) {

            // Auxiliary Section:
            .nop => {},

            .pop => {
                const value = try self.pop();
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
            .push_void => try self.push(Value.initVoid()),

            // Memory Access Section:

            .store_global_idx => |i| {
                if (i.value >= self.environment.scriptGlobals.len)
                    return error.InvalidGlobalVariable;

                const value = try self.pop();

                self.environment.scriptGlobals[i.value].replaceWith(value);
            },

            .load_global_idx => |i| {
                if (i.value >= self.environment.scriptGlobals.len)
                    return error.InvalidGlobalVariable;

                const value = try self.environment.scriptGlobals[i.value].clone();
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

                const value = try ctx.locals[i.value].clone();
                errdefer value.deinit();

                try self.push(value);
            },

            .store_global_name => |i| {
                const global_kv = self.environment.namedGlobals.get(i.value);
                if (global_kv == null)
                    return error.InvalidGlobalVariable;
                const global = &global_kv.?.value;

                const value = try self.pop();
                errdefer value.deinit();

                try global.set(value);
            },

            .load_global_name => |i| {
                const global_kv = self.environment.namedGlobals.get(i.value);
                if (global_kv == null)
                    return error.InvalidGlobalVariable;
                const global = &global_kv.?.value;

                const value = try global.get();
                errdefer value.deinit();

                try self.push(value);
            },

            // Array Operations:

            .array_pack => |i| {
                var array = try Array.init(self.allocator, i.value);
                errdefer array.deinit();

                for (array.contents) |*item| {
                    const value = try self.pop();
                    errdefer value.deinit();

                    item.replaceWith(value);
                }

                try self.push(Value.fromArray(array));
            },

            .array_load => {
                var array_val = try self.pop();
                defer array_val.deinit();

                const index_val = try self.pop();
                defer index_val.deinit();

                const item = try getArrayItem(&array_val, index_val);

                const dupe = try item.clone();
                errdefer dupe.deinit();

                try self.push(dupe);
            },

            .array_store => {
                var array_val = try self.pop();
                errdefer array_val.deinit();

                const index_val = try self.pop();
                defer index_val.deinit();

                const value = try self.pop();
                defer value.deinit();

                const item = try getArrayItem(&array_val, index_val);

                item.replaceWith(value);

                try self.push(array_val);
            },

            // Iterator Section:
            .iter_make => {
                const array_val = try self.pop();
                errdefer array_val.deinit();

                // is still owned by array_val and will be destroyed in case of array.
                const array = try array_val.toArray();

                try self.push(Value.fromEnumerator(Enumerator.initFromOwned(array)));
            },

            .iter_next => {
                const enumerator_val = try self.peek();
                const enumerator = try enumerator_val.getEnumerator();
                if (enumerator.next()) |value| {
                    self.push(value) catch |err| {
                        value.deinit();
                        return err;
                    };
                    try self.push(Value.initBoolean(true));
                } else {
                    try self.push(Value.initBoolean(false));
                }
            },

            // Control Flow Section:

            .ret => {
                const call = self.calls.pop();
                defer self.deinitContext(call);

                // Restore stack balance
                while (self.stack.len > call.stackBalance) {
                    const item = self.stack.pop();
                    item.deinit();
                }

                // No more context to execute: we have completed execution
                if (self.calls.len == 0)
                    return .completed;

                try self.push(Value.initVoid());
            },

            .retval => {
                const value = try self.pop();
                errdefer value.deinit();

                const call = self.calls.pop();
                defer self.deinitContext(call);

                // Restore stack balance
                while (self.stack.len > call.stackBalance) {
                    const item = self.stack.pop();
                    item.deinit();
                }

                try self.push(value);

                // No more context to execute: we have completed execution
                if (self.calls.len == 0)
                    return .completed;
            },

            .jmp => |target| {
                ctx.decoder.offset = target.value;
            },

            .jif, .jnf => |target| {
                const value = try self.pop();
                defer value.deinit();

                const boolean = try value.toBoolean();

                if (boolean == (instruction == .jnf)) {
                    ctx.decoder.offset = target.value;
                }
            },

            .call_fn => |call| {
                const fun_kv = self.environment.functions.get(call.function);
                if (fun_kv == null)
                    return error.FunctionNotFound;
                switch (fun_kv.?.value) {
                    .script => |fun| {
                        var context = try self.createContext(fun);
                        errdefer self.deinitContext(context);

                        try self.readLocals(call, context.locals);

                        // Fixup stack balance after popping all locals
                        context.stackBalance = self.stack.len;

                        try self.calls.append(context);
                    },
                    .syncUser => |fun| {
                        var locals = try self.allocator.alloc(Value, call.argc);
                        for (locals) |*l| {
                            l.* = Value.initVoid();
                        }
                        defer {
                            for (locals) |l| {
                                l.deinit();
                            }
                            self.allocator.free(locals);
                        }

                        try self.readLocals(call, locals);

                        const result = try fun.call(fun.context, locals);
                        errdefer result.deinit();

                        try self.push(result);
                    },
                    .asyncUser => |fun| {
                        var locals = try self.allocator.alloc(Value, call.argc);
                        for (locals) |*l| {
                            l.* = Value.initVoid();
                        }
                        defer {
                            for (locals) |l| {
                                l.deinit();
                            }
                            self.allocator.free(locals);
                        }

                        try self.readLocals(call, locals);

                        self.currentAsynCall = try fun.call(fun.context, locals);
                        self.currentAsynCall.?.object = null;

                        return .yield;
                    },
                }
            },

            // Logic Section:
            .bool_and => {
                const lhs = try self.pop();
                defer lhs.deinit();

                const rhs = try self.pop();
                defer rhs.deinit();

                const a = try lhs.toBoolean();
                const b = try rhs.toBoolean();

                try self.push(Value.initBoolean(a and b));
            },

            .bool_or => {
                const lhs = try self.pop();
                defer lhs.deinit();

                const rhs = try self.pop();
                defer rhs.deinit();

                const a = try lhs.toBoolean();
                const b = try rhs.toBoolean();

                try self.push(Value.initBoolean(a or b));
            },

            .bool_not => {
                const val = try self.pop();
                defer val.deinit();

                const a = try val.toBoolean();

                try self.push(Value.initBoolean(!a));
            },

            // Arithmetic Section:

            .negate => {
                const value = try self.pop();
                defer value.deinit();

                const num = try value.toNumber();

                try self.push(Value.initNumber(-num));
            },

            .add => {
                const rhs = try self.pop();
                defer rhs.deinit();

                const lhs = try self.pop();
                defer lhs.deinit();

                if (@as(TypeId, lhs) != @as(TypeId, rhs))
                    return error.TypeMismatch;

                switch (lhs) {
                    .number => {
                        try self.push(Value.initNumber(lhs.number + rhs.number));
                    },

                    .string => {
                        const lstr = lhs.string.contents;
                        const rstr = rhs.string.contents;

                        const result = try self.allocator.alloc(u8, lstr.len + rstr.len);
                        errdefer self.allocator.free(result);

                        std.mem.copy(u8, result[0..lstr.len], lstr);
                        std.mem.copy(u8, result[lstr.len..result.len], rstr);

                        try self.push(Value.fromString(String{
                            .allocator = self.allocator,
                            .contents = result,
                        }));
                    },

                    .array => {
                        const larr = lhs.array.contents;
                        const rarr = rhs.array.contents;

                        var result = try Array.init(self.allocator, larr.len + rarr.len);
                        errdefer result.deinit();

                        for (larr) |*item, i| {
                            result.contents[i].exchangeWith(item);
                        }

                        for (rarr) |*item, i| {
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
                const lhs = try self.pop();
                defer lhs.deinit();

                const rhs = try self.pop();
                defer rhs.deinit();

                try self.push(Value.initBoolean(lhs.eql(rhs)));
            },
            .neq => {
                const lhs = try self.pop();
                defer lhs.deinit();

                const rhs = try self.pop();
                defer rhs.deinit();

                try self.push(Value.initBoolean(!lhs.eql(rhs)));
            },
            .less => try self.executeCompareValues(.lt, false),
            .less_eq => try self.executeCompareValues(.lt, true),
            .greater => try self.executeCompareValues(.gt, false),
            .greater_eq => try self.executeCompareValues(.gt, true),

            // Deperecated Section:
            .scope_push, .scope_pop, .declare => return error.DeprectedInstruction,
            else => {
                std.debug.warn("Instruction `{}` not implemented yet!\n", .{
                    @tagName(@as(InstructionName, instruction)),
                });
                return error.NotImplementedYet; // @panic("Not implemented yet!"),
            },
        }

        return null;
    }

    /// Reads a number of call arguments into a slice.
    /// If an error happens, all items in `locals` are valid and must be deinitialized.
    fn readLocals(self: *Self, call: Instruction.CallArg, locals: []Value) !void {
        var i: usize = 0;
        while (i < call.argc) : (i += 1) {
            const value = try self.pop();
            if (i < locals.len) {
                locals[i].replaceWith(value);
            } else {
                value.deinit(); // Discard the value
            }
        }
    }

    fn executeCompareValues(self: *Self, wantedOrder: std.math.Order, allowEql: bool) !void {
        const rhs = try self.pop();
        defer rhs.deinit();

        const lhs = try self.pop();
        defer lhs.deinit();

        if (@as(TypeId, lhs) != @as(TypeId, rhs))
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

    fn getArrayItem(array_val: *Value, index_val: Value) !*Value {
        const array = try array_val.getArray();
        const flt_index = try index_val.toNumber();

        if (flt_index < 0)
            return error.IndexOutOfRange;

        const index = try floatToInt(usize, std.math.trunc(flt_index));
        std.debug.assert(index >= 0);
        if (index >= array.contents.len)
            return error.IndexOutOfRange;

        return &array.contents[index];
    }

    fn floatToInt(comptime T: type, flt: var) error{Overflow}!T {
        comptime std.debug.assert(@typeId(T) == .Int); // must pass an integer
        comptime std.debug.assert(@typeId(@TypeOf(flt)) == .Float); // must pass a float
        if (flt > std.math.maxInt(T)) {
            return error.Overflow;
        } else if (flt < std.math.minInt(T)) {
            return error.Overflow;
        } else {
            return @floatToInt(T, flt);
        }
    }

    const SingleResult = enum {
        /// The program has encountered an asynchronous function
        completed,

        /// execution and waits for completion.
        yield,
    };

    fn executeNumberArithmetic(self: *Self, operator: fn (f64, f64) error{DivideByZero}!f64) !void {
        const rhs = try self.pop();
        defer rhs.deinit();

        const lhs = try self.pop();
        defer lhs.deinit();

        const n_lhs = try lhs.toNumber();
        const n_rhs = try rhs.toNumber();

        const result = try operator(n_lhs, n_rhs);

        try self.push(Value.initNumber(result));
    }
};

test "VM" {
    _ = VM;
    _ = VM.init;
    _ = VM.deinit;
    _ = VM.execute;
}
