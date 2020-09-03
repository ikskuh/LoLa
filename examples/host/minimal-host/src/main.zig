const std = @import("std");
const lola = @import("lola");

const example_source =
    \\Print("Hello, World!");
    \\
;

pub fn main() anyerror!u8 {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();

    const allocator = &gpa_state.allocator;

    // Step 1: Compile the source code into a compile unit

    // This stores the error messages and warnings, we
    // just keep it and print all messages on exit (if any).
    var diagnostics = lola.compiler.Diagnostics.init(allocator);
    defer {
        for (diagnostics.messages.items) |msg| {
            std.debug.print("{}\n", .{msg});
        }
        diagnostics.deinit();
    }

    // This compiles a piece of source code into a compile unit.
    // A compile unit is a piece of LoLa IR code with metadata for
    // all existing functions, debug symbols and so on. It can be loaded into
    // a environment and be executed.
    var compile_unit = (try lola.compiler.compile(allocator, &diagnostics, "example_source", example_source)) orelse {
        std.debug.print("failed to compile example_source!\n", .{});
        return 1;
    };
    defer compile_unit.deinit();

    // A object pool is required for garabge collecting object handles
    // stored in several LoLa environments and virtual machines.
    var pool = lola.runtime.ObjectPool.init(allocator);
    defer pool.deinit();

    // A environment stores global variables and provides functions
    // to the virtual machines. It is also a possible LoLa object that
    // can be passed into virtual machines.
    var env = try lola.runtime.Environment.init(allocator, &compile_unit, &pool);
    defer env.deinit();

    // Install both standard and runtime library into
    // our environment. You can see how to implement custom
    // functions if you check out the implementation of both
    // libraries!
    try lola.libs.std.install(&env, allocator);
    try lola.libs.runtime.install(&env, allocator);

    // Create a virtual machine that is used to execute LoLa bytecode.
    // Using `.init` will always run the top-level code.
    var vm = try lola.runtime.VM.init(allocator, &env);
    defer vm.deinit();

    // The main interpreter loop:
    while (true) {

        // Run the virtual machine for up to 150 instructions
        var result = vm.execute(150) catch |err| {
            // When the virtua machine panics, we receive a Zig error
            std.debug.print("LoLa panic: {}\n", .{@errorName(err)});
            return 1;
        };

        // Prepare a garbage collection cycle:
        pool.clearUsageCounters();

        // Mark all objects currently referenced in the environment
        try pool.walkEnvironment(env);

        // Mark all objects currently referenced in the virtual machine
        try pool.walkVM(vm);

        // Delete all objects that are not referenced by our system anymore
        pool.collectGarbage();

        switch (result) {
            // This means that our script execution has ended and
            // the top-level code has come to an end
            .completed => break,

            // This means the VM has exhausted its provided instruction quota
            // and returned control to the host.
            .exhausted => {
                std.debug.print("Execution exhausted after 150 instructions!\n", .{});
            },

            // This means the virtual machine was suspended via a async function call.
            .paused => std.time.sleep(100),
        }
    }

    return 0;
}
