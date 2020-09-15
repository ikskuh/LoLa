const std = @import("std");
const lola = @import("lola");
const argsParser = @import("args");
const build_options = @import("build_options");

// This is our global object pool that is back-referenced
// by the runtime library.
pub const ObjectPool = lola.runtime.ObjectPool([_]type{
    lola.libs.runtime.LoLaList,
    lola.libs.runtime.LoLaDictionary,
});

var allocator: *std.mem.Allocator = undefined;
var compile_unit: lola.CompileUnit = undefined;
var pool: ObjectPool = undefined;
var environment: lola.runtime.Environment = undefined;
var vm: lola.runtime.VM = undefined;

pub fn milliTimestamp() usize {
    // Implement this!
    return 0;
}

const API = struct {
    fn validate(source: []const u8) !void {
        var diagnostics = lola.compiler.Diagnostics.init(allocator);
        defer {
            for (diagnostics.messages.items) |msg| {
                // TODO: std.debug.print("{}\n", .{msg});
            }
            diagnostics.deinit();
        }

        // This compiles a piece of source code into a compile unit.
        // A compile unit is a piece of LoLa IR code with metadata for
        // all existing functions, debug symbols and so on. It can be loaded into
        // a environment and be executed.
        var temp_compile_unit = (try lola.compiler.compile(allocator, &diagnostics, "example_source", source)) orelse {
            // TODO: std.debug.print("failed to compile example_source!\n", .{});
            return;
        };
        temp_compile_unit.deinit();
    }

    fn initInterpreter(source: []const u8) !void {
        var diagnostics = lola.compiler.Diagnostics.init(allocator);
        defer {
            for (diagnostics.messages.items) |msg| {
                // TODO: std.debug.print("{}\n", .{msg});
            }
            diagnostics.deinit();
        }

        // This compiles a piece of source code into a compile unit.
        // A compile unit is a piece of LoLa IR code with metadata for
        // all existing functions, debug symbols and so on. It can be loaded into
        // a environment and be executed.
        compile_unit = (try lola.compiler.compile(allocator, &diagnostics, "example_source", source)) orelse {
            // TODO: std.debug.print("failed to compile example_source!\n", .{});
            return error.FailedToCompile;
        };
        errdefer compile_unit.deinit();

        pool = ObjectPool.init(allocator);
        errdefer pool.deinit();

        environment = try lola.runtime.Environment.init(allocator, &compile_unit, pool.interface());
        errdefer environment.deinit();

        try lola.libs.std.install(&environment, allocator);
        // try lola.libs.runtime.install(&environment, allocator);

        vm = try lola.runtime.VM.init(allocator, &environment);
    }

    fn deinitInterpreter() void {
        vm.deinit();
        environment.deinit();
        pool.deinit();
        compile_unit.deinit();
    }

    fn stepInterpreter(steps: u32) !void {
        // Run the virtual machine for up to 150 instructions
        var result = vm.execute(150) catch |err| {
            // When the virtua machine panics, we receive a Zig error
            // std.debug.print("LoLa panic: {}\n", .{@errorName(err)});
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

        // switch (result) {
        //     // This means that our script execution has ended and
        //     // the top-level code has come to an end
        //     .completed => break,

        //     // This means the VM has exhausted its provided instruction quota
        //     // and returned control to the host.
        //     .exhausted => {
        //         std.debug.print("Execution exhausted after 150 instructions!\n", .{});
        //     },

        //     // This means the virtual machine was suspended via a async function call.
        //     .paused => std.time.sleep(100),
        // }
    }
};

export fn initialize() void {
    unreachable;
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
