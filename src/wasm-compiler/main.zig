const std = @import("std");
const lola = @import("lola");
const zee_alloc = @import("zee_alloc");

// This is our global object pool that is back-referenced
// by the runtime library.
pub const ObjectPool = lola.runtime.ObjectPool([_]type{
    lola.libs.runtime.LoLaList,
    lola.libs.runtime.LoLaDictionary,
});

var allocator: *std.mem.Allocator = zee_alloc.ZeeAllocDefaults.wasm_allocator;
var compile_unit: lola.CompileUnit = undefined;
var pool: ObjectPool = undefined;
var environment: lola.runtime.Environment = undefined;
var vm: lola.runtime.VM = undefined;
var is_done: bool = true;

pub fn milliTimestamp() usize {
    return JS.millis();
}

const JS = struct {
    extern fn compileLog(data: [*]const u8, len: u32) void;

    extern fn millis() usize;
};

const API = struct {
    fn writeLog(_: void, str: []const u8) !usize {
        JS.compileLog(str.ptr, @intCast(u32, str.len));
        return str.len;
    }

    var debug_writer = std.io.Writer(void, error{}, writeLog){ .context = {} };

    fn validate(source: []const u8) !void {
        var diagnostics = lola.compiler.Diagnostics.init(allocator);
        defer diagnostics.deinit();

        // This compiles a piece of source code into a compile unit.
        // A compile unit is a piece of LoLa IR code with metadata for
        // all existing functions, debug symbols and so on. It can be loaded into
        // a environment and be executed.
        var temp_compile_unit = try lola.compiler.compile(allocator, &diagnostics, "code", source);

        for (diagnostics.messages.items) |msg| {
            std.fmt.format(debug_writer, "{}\n", .{msg}) catch unreachable;
        }

        if (temp_compile_unit) |*unit|
            unit.deinit();
    }

    fn initInterpreter(source: []const u8) !void {
        var diagnostics = lola.compiler.Diagnostics.init(allocator);
        diagnostics.deinit();

        const compile_unit_or_none = try lola.compiler.compile(allocator, &diagnostics, "code", source);

        for (diagnostics.messages.items) |msg| {
            std.fmt.format(debug_writer, "{}\n", .{msg}) catch unreachable;
        }

        compile_unit = compile_unit_or_none orelse return error.FailedToCompile;
        errdefer compile_unit.deinit();

        pool = ObjectPool.init(allocator);
        errdefer pool.deinit();

        environment = try lola.runtime.Environment.init(allocator, &compile_unit, pool.interface());
        errdefer environment.deinit();

        try lola.libs.std.install(&environment, allocator);
        // try lola.libs.runtime.install(&environment, allocator);

        try environment.installFunction("Print", lola.runtime.Function.initSimpleUser(struct {
            fn Print(_environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
                // const allocator = context.get(std.mem.Allocator);
                for (args) |value, i| {
                    switch (value) {
                        .string => |str| try debug_writer.writeAll(str.contents),
                        else => try debug_writer.print("{}", .{value}),
                    }
                }
                try debug_writer.writeAll("\r\n");
                return .void;
            }
        }.Print));

        try environment.installFunction("Write", lola.runtime.Function.initSimpleUser(struct {
            fn Write(_environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
                // const allocator = context.get(std.mem.Allocator);
                for (args) |value, i| {
                    switch (value) {
                        .string => |str| try debug_writer.writeAll(str.contents),
                        else => try debug_writer.print("{}", .{value}),
                    }
                }
                return .void;
            }
        }.Write));

        vm = try lola.runtime.VM.init(allocator, &environment);
        errdefer vm.deinit();

        is_done = false;
    }

    fn deinitInterpreter() void {
        if (!is_done) {
            vm.deinit();
            environment.deinit();
            pool.deinit();
            compile_unit.deinit();
        }
        is_done = true;
    }

    fn stepInterpreter(steps: u32) !void {
        if (is_done)
            return error.InvalidInterpreterState;

        // Run the virtual machine for up to 150 instructions
        var result = vm.execute(150) catch |err| {
            // When the virtua machine panics, we receive a Zig error
            try std.fmt.format(debug_writer, "LoLa panic: {}\n", .{@errorName(err)});
            return error.LoLaPanic;
        };

        // Prepare a garbage collection cycle:
        pool.clearUsageCounters();

        // Mark all objects currently referenced in the environment
        try pool.walkEnvironment(environment);

        // Mark all objects currently referenced in the virtual machine
        try pool.walkVM(vm);

        // Delete all objects that are not referenced by our system anymore
        pool.collectGarbage();

        switch (result) {
            // This means that our script execution has ended and
            // the top-level code has come to an end
            .completed => {
                // deinitialize everything, stop execution
                deinitInterpreter();
                return;
            },

            // This means the VM has exhausted its provided instruction quota
            // and returned control to the host.
            .exhausted => {},

            // This means the virtual machine was suspended via a async function call.
            .paused => {},
        }
    }
};

export fn initialize() void {
    // nothing to init atm
}

export fn malloc(len: usize) [*]u8 {
    var slice = allocator.alloc(u8, len) catch unreachable;
    return slice.ptr;
}

export fn free(mem: [*]u8, len: usize) void {
    allocator.free(mem[0..len]);
}

const LoLaError = error{
    OutOfMemory,
    FailedToCompile,
    SyntaxError,
    InvalidCode,
    AlreadyDeclared,
    TooManyVariables,
    TooManyLabels,
    LabelAlreadyDefined,
    Overflow,
    NotInLoop,
    VariableNotFound,
    InvalidStoreTarget,

    LoLaPanic,

    AlreadyExists,
    InvalidObject,

    InvalidInterpreterState,
};
fn mapError(err: LoLaError) u8 {
    return switch (err) {
        error.OutOfMemory => 1,
        error.FailedToCompile => 2,
        error.SyntaxError => 3,
        error.InvalidCode => 3,
        error.AlreadyDeclared => 3,
        error.TooManyVariables => 3,
        error.TooManyLabels => 3,
        error.LabelAlreadyDefined => 3,
        error.Overflow => 3,
        error.NotInLoop => 3,
        error.VariableNotFound => 3,
        error.InvalidStoreTarget => 3,
        error.AlreadyExists => 3,
        error.LoLaPanic => 4,
        error.InvalidObject => 5,
        error.InvalidInterpreterState => 6,
    };
}

export fn validate(source: [*]const u8, source_len: usize) u8 {
    API.validate(source[0..source_len]) catch |err| return mapError(err);
    return 0;
}

export fn initInterpreter(source: [*]const u8, source_len: usize) u8 {
    API.initInterpreter(source[0..source_len]) catch |err| return mapError(err);
    return 0;
}

export fn deinitInterpreter() void {
    API.deinitInterpreter();
}

export fn stepInterpreter(steps: u32) u8 {
    API.stepInterpreter(steps) catch |err| return mapError(err);
    return 0;
}

export fn isInterpreterDone() bool {
    return is_done;
}
