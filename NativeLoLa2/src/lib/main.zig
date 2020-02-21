const std = @import("std");
// Import modules to reduce file size
usingnamespace @import("value.zig");
usingnamespace @import("ir.zig");
usingnamespace @import("compile_unit.zig");
usingnamespace @import("decoder.zig");
usingnamespace @import("named_global.zig");
usingnamespace @import("disassembler.zig");
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
        locals: []Value,
        decoder: Decoder,
    };

    allocator: *std.mem.Allocator,
    environment: *const Environment,
    stack: std.ArrayList(Value),
    calls: std.ArrayList(Context),

    /// Initialize a new virtual machine that will run the given environment.
    pub fn init(allocator: *std.mem.Allocator, environment: *const Environment) !Self {
        var vm = Self{
            .allocator = allocator,
            .environment = environment,
            .stack = std.ArrayList(Value).init(allocator),
            .calls = std.ArrayList(Context).init(allocator),
        };
        errdefer vm.stack.deinit();
        errdefer vm.calls.deinit();

        // Initialize with special "init context" that runs the script itself
        // and hosts the global variables.
        _ = try vm.pushContext(ScriptFunction{
            .compileUnit = environment.compileUnit,
            .entryPoint = 0, // start at the very first byte
            .localCount = 0, // and don't store any global variables as the "core" context is not a function
        });

        return vm;
    }

    pub fn deinit(self: Self) void {
        for (self.stack.toSliceConst()) |v| {
            v.deinit();
        }
        for (self.calls.toSliceConst()) |c| {
            for (c.locals) |v| {
                v.deinit();
            }
            self.allocator.free(c.locals);
        }
        self.stack.deinit();
        self.calls.deinit();
    }

    /// Pushes a new execution context to the call stack.
    fn pushContext(self: *Self, fun: ScriptFunction) !*Context {
        const ctx = try self.calls.addOne();
        errdefer _ = self.calls.pop();

        ctx.* = Context{
            .decoder = Decoder.init(fun.compileUnit.code),
            .locals = undefined,
        };
        ctx.locals = try self.allocator.alloc(Value, fun.localCount);

        return ctx;
    }

    /// Pushes the value. Will take ownership of the pushed value.
    fn push(self: *Self, value: Value) !void {
        try self.stack.append(value);
    }

    /// Peeks at the top of the stack. The returned value is still owned
    /// by the stack.
    fn peek(self: Self) !Value {
        const slice = self.stack.toSliceConst();
        if (slice.len == 0)
            return error.StackImbalance;
        return slice[slice.len - 1];
    }

    /// Pops a value from the stack. The ownership will be transferred to the caller.
    fn pop(self: *Self) !Value {
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

            switch (try self.executeSingle()) {
                .completed => return ExecutionResult.completed,
                .yield => return ExecutionResult.paused,
                .@"continue" => {},
            }
        }
    }

    /// Executes a single instruction and returns the state of the machine.
    fn executeSingle(self: *Self) !SingleResult {
        const ctx = &self.calls.toSlice()[self.calls.len - 1];

        const instruction = try ctx.decoder.read(Instruction);
        switch (instruction) {
            else => @panic("Not implemented yet!"),
        }
    }

    const SingleResult = enum {
        /// The program has encountered an asynchronous function
        completed,

        /// execution and waits for completion.
        yield,

        /// The instruction has finished and awaits execution of the next.
        @"continue",
    };
};

test "VM" {
    _ = VM;
    _ = VM.init;
    _ = VM.deinit;
    _ = VM.pushContext;
    _ = VM.execute;
}

// auto const i = ctx.fetch_instruction();
// switch(i)
// {
// case IL::Instruction::nop:
//     return continue_execution;

// case IL::Instruction::push_num:
//     ctx.push(ctx.fetch_number());
//     return continue_execution;

// case IL::Instruction::push_str:
//     ctx.push(ctx.fetch_string());
//     return continue_execution;

// case IL::Instruction::store_local:
// {
//         auto const index = ctx.fetch_u16();
//         if(index >= ctx.locals.size())
//             throw Error::InvalidVariable;
//         ctx.locals.at(index) = ctx.pop();
//         return continue_execution;
// }

// case IL::Instruction::load_local:
// {
//         auto const index = ctx.fetch_u16();
//         if(index >= ctx.locals.size())
//             throw Error::InvalidVariable;
//         ctx.push(ctx.locals.at(index));
//         return continue_execution;
// }

// case IL::Instruction::ret:
//     return Void { };

// case IL::Instruction::retval:
//     return ctx.pop();

// case IL::Instruction::pop:
//     ctx.pop();
//     return continue_execution;

// case IL::Instruction::jmp:               // [ target:u32 ]
// {
//     auto const target = ctx.fetch_u32();
//     if(target >= ctx.code->code.size())
//         throw Error::InvalidPointer;
//     ctx.offset = target;
//     return continue_execution;
// }
// case IL::Instruction::jnf:               // [ target:u32 ]
// {
//     auto const target = ctx.fetch_u32();
//     auto const take_jump = to_boolean(ctx.pop());
//     if(take_jump)
//     {
//         if(target >= ctx.code->code.size())
//             throw Error::InvalidPointer;
//         ctx.offset = target;
//     }
//     return continue_execution;
// }

// case IL::Instruction::jif:               // [ target:u32 ]
// {
//     auto const target = ctx.fetch_u32();
//     auto const take_jump = not to_boolean(ctx.pop());
//     if(take_jump)
//     {
//         if(target >= ctx.code->code.size())
//             throw Error::InvalidPointer;
//         ctx.offset = target;
//     }
//     return continue_execution;
// }

// #define BINARY_OPERATOR(_Convert, _Operator) \
//     { \
//         auto const rhs = ctx.pop(); \
//         auto const lhs = ctx.pop(); \
//         ctx.push(_Convert(lhs) _Operator _Convert(rhs)); \
//         return continue_execution; \
//     }

// #define UNARY_OPERATOR(_Convert, _Operator) \
//     { \
//         auto const value = ctx.pop(); \
//         ctx.push(_Operator _Convert(value)); \
//         return continue_execution; \
//     } \

// case IL::Instruction::add:
// {
//     auto const rhs = ctx.pop();
//     auto const lhs = ctx.pop();
//     switch(typeOf(lhs))
//     {
//     case TypeID::Number:
//         ctx.push(to_number(lhs) + to_number(rhs));
//         break;

//     case TypeID::String:
//         ctx.push(to_string(lhs) + to_string(rhs));
//         break;

//     case TypeID::Array:
//         ctx.push(to_array(lhs) + to_array(rhs));
//         break;

//     case TypeID::Void:
//     case TypeID::Object:
//     case TypeID::Boolean:
//     case TypeID::Enumerator:
//         throw Error::InvalidOperator;
//     }
//     return continue_execution;
// }

// case IL::Instruction::sub:      BINARY_OPERATOR(to_number, -)
// case IL::Instruction::mul:      BINARY_OPERATOR(to_number, *)
// case IL::Instruction::div:      BINARY_OPERATOR(to_number, /)
// case IL::Instruction::mod:      BINARY_OPERATOR(to_numberhack, %)

// case IL::Instruction::bool_and: BINARY_OPERATOR(to_boolean, and)
// case IL::Instruction::bool_or:  BINARY_OPERATOR(to_boolean, or)

// case IL::Instruction::eq: BINARY_OPERATOR(, ==)
// case IL::Instruction::neq: BINARY_OPERATOR(, !=)
// case IL::Instruction::less_eq: BINARY_OPERATOR(to_number, <=)
// case IL::Instruction::greater_eq: BINARY_OPERATOR(to_number, >=)
// case IL::Instruction::less: BINARY_OPERATOR(to_number, <)
// case IL::Instruction::greater: BINARY_OPERATOR(to_number, >)

// case IL::Instruction::bool_not: UNARY_OPERATOR(to_boolean, not)
// case IL::Instruction::negate: UNARY_OPERATOR(to_number, -)

// case IL::Instruction::array_pack:         // [ num:u16 ]
// {
//     auto const cnt = ctx.fetch_u16();
//     Array array;
//     array.resize(cnt);
//     for(size_t i = 0; i < cnt; i++)
//     {
//         array[i] = ctx.pop();
//     }
//     ctx.push(array);
//     return continue_execution;
// }

// case IL::Instruction::call_fn:            // [ fun:str ] [argc:u8 ]
// {
//     auto const name = ctx.fetch_string();
//     auto const argc = ctx.fetch_u8();
//     if(auto it = env.functions.find(name); it != env.functions.end())
//     {
//         std::vector<Value> argv;
//         argv.resize(argc);
//         for(size_t i = 0; i < argc; i++)
//             argv[i] = ctx.pop();

//         auto fnOrValue = it->second->call(argv.data(), argv.size());

//         if(std::holds_alternative<Value>(fnOrValue))
//         {
//             ctx.push(std::get<Value>(fnOrValue));
//             return continue_execution;
//         }
//         else
//         {
//             assert(std::holds_alternative<std::unique_ptr<FunctionCall>>(fnOrValue));
//             vm.code_stack.emplace_back(std::move(std::get<std::unique_ptr<FunctionCall>>(fnOrValue)));
//             return yield_execution;
//         }
//     }
//     else
//     {
//         std::cerr << "function " << name << " not found!" << std::endl;
//         throw Error::UnsupportedFunction;
//     }
// }

// case IL::Instruction::call_obj:          // [ fun:str ] [argc:u8 ]
// {
//     auto const name = ctx.fetch_string();
//     auto const argc = ctx.fetch_u8();

//     Value const obj_val = ctx.pop();
//     if(typeOf(obj_val) != TypeID::Object)
//         throw Error::TypeMismatch;

//     auto obj = std::get<Object>(obj_val).lock();
//     if(not obj)
//         throw Error::ObjectDisposed;
//     if(auto fun = obj->getFunction(name); fun)
//     {
//         std::vector<Value> argv;
//         argv.resize(argc);
//         for(size_t i = 0; i < argc; i++)
//             argv[i] = ctx.pop();

//         auto fnOrValue = (*fun)->call(argv.data(), argv.size());

//         if(std::holds_alternative<Value>(fnOrValue))
//         {
//             ctx.push(std::get<Value>(fnOrValue));
//             return continue_execution;
//         }
//         else
//         {
//             assert(std::holds_alternative<std::unique_ptr<FunctionCall>>(fnOrValue));
//             vm.code_stack.emplace_back(std::move(std::get<std::unique_ptr<FunctionCall>>(fnOrValue)));
//             return yield_execution;
//         }
//     }
//     else
//     {
//         std::cerr << "method " << name << " not found!" << std::endl;
//         throw Error::UnsupportedFunction;
//     }
// }

// case IL::Instruction::store_global_idx:       // [ idx:u16 ]
// {
//     auto const index = ctx.fetch_u16();
//     if(index >= env.script_globals.size())
//         throw Error::InvalidVariable;
//     env.script_globals.at(index) = ctx.pop();
//     return continue_execution;
// }

// case IL::Instruction::load_global_idx:        // [ idx:u16 ]
// {
//     auto const index = ctx.fetch_u16();
//     if(index >= env.script_globals.size())
//         throw Error::InvalidVariable;
//     ctx.push(env.script_globals.at(index));
//     return continue_execution;
// }

// case IL::Instruction::array_store: // pops value, then index, then array, pushes array
// {
//     auto array = to_array(ctx.pop());
//     auto const index = size_t(to_number(ctx.pop()));
//     auto const value = ctx.pop();

//     array.at(index) = value;

//     ctx.push(array);

//     return continue_execution;
// }

// case IL::Instruction::array_load:
// {
//     auto array = to_array(ctx.pop());
//     auto const index = size_t(to_number(ctx.pop()));

//     ctx.push(array.at(index));

//     return continue_execution;
// }

// case IL::Instruction::iter_make:
// {
//     auto array = to_array(ctx.pop());
//     ctx.push(Enumerator(array));
//     return continue_execution;
// }

// case IL::Instruction::iter_next:
// {
//     auto & top = ctx.peek();
//     if(typeOf(top) != TypeID::Enumerator)
//         throw Error::TypeMismatch;

//     auto & iter = std::get<Enumerator>(top);
//     if(iter.next())
//     {
//         ctx.push(iter.value());
//         ctx.push(true);
//     }
//     else
//     {
//         ctx.push(false);
//     }

//     return continue_execution;
// }

// case IL::Instruction::store_global_name:       // [ var:str ]
// {
//     auto const name = ctx.fetch_string();
//     auto const val = ctx.pop();

//     if(auto it = env.known_globals.find(name); it != env.known_globals.end())
//     {
//         using Getter = Environment::Getter;
//         using Setter = Environment::Setter;

//         auto & var = it->second;
//         if(std::holds_alternative<Value>(var))
//         {
//             std::get<Value>(var) = val;
//         }
//         else if(std::holds_alternative<Value*>(var))
//         {
//             *std::get<Value*>(var) = val;
//         }
//         else if(std::holds_alternative<std::pair<Getter, Setter>>(var))
//         {
//             auto & pair = std::get<std::pair<Getter, Setter>>(var);
//             if(pair.second)
//                 pair.second(val);
//             else
//                 throw Error::ReadOnlyVariable;
//         }
//         else {
//             assert(false and "not implemented yet");
//         }
//     }
//     else
//     {
//         throw Error::InvalidVariable;
//     }
//     return continue_execution;
// }
// case IL::Instruction::load_global_name:        // [ var:str ]
// {
//     auto const name = ctx.fetch_string();
//     if(auto it = env.known_globals.find(name); it != env.known_globals.end())
//     {
//         using Getter = Environment::Getter;
//         using Setter = Environment::Setter;

//         Value result;
//         auto const & var = it->second;
//         if(std::holds_alternative<Value>(var))
//         {
//             result = std::get<Value>(var);
//         }
//         else if(std::holds_alternative<Value*>(var))
//         {
//             result = *std::get<Value*>(var);
//         }
//         else if(std::holds_alternative<std::pair<Getter, Setter>>(var))
//         {
//             auto & pair = std::get<std::pair<Getter, Setter>>(var);
//             if(pair.first)
//                 result = pair.first();
//             else
//                 throw Error::ReadOnlyVariable;
//         }
//         else {
//             assert(false and "not implemented yet");
//         }
//         ctx.push(result);
//     }
//     else
//     {
//         throw Error::InvalidVariable;
//     }
//     return continue_execution;
// }
// }
