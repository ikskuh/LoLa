const std = @import("std");
const lola = @import("lola");

////
// Serialization API example:
// This example shows how to save a whole-program state into a buffer
// and restore that later to continue execution.
//

// NOTE: This example is work-in-progress!

const example_source =
    \\for(i in Range(1, 100)) {
    \\  Print("Round ", i);
    \\}
;

pub const ObjectPool = lola.runtime.ObjectPool([_]type{
    lola.libs.runtime.LoLaDictionary,
    lola.libs.runtime.LoLaList,
});

pub fn main() anyerror!void {

    // this will store our intermediate data
    var serialization_buffer: [4096]u8 = undefined;

    {
        var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa_state.deinit();

        try run_serialization(
            &gpa_state.allocator,
            &serialization_buffer,
        );
    }

    {
        var stdout = std.io.getStdOut().writer();
        try stdout.writeAll("\n");
        try stdout.writeAll("-----------------------------------\n");
        try stdout.writeAll("\n");
    }

    {
        var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa_state.deinit();

        try run_deserialization(
            &gpa_state.allocator,
            &serialization_buffer,
        );
    }
}

fn run_serialization(allocator: *std.mem.Allocator, serialization_buffer: []u8) !void {
    var diagnostics = lola.compiler.Diagnostics.init(allocator);
    defer {
        for (diagnostics.messages.items) |msg| {
            std.debug.print("{}\n", .{msg});
        }
        diagnostics.deinit();
    }

    var compile_unit = (try lola.compiler.compile(allocator, &diagnostics, "example_source", example_source)) orelse return error.FailedToCompile;
    defer compile_unit.deinit();

    var pool = ObjectPool.init(allocator);
    defer pool.deinit();

    var env = try lola.runtime.Environment.init(allocator, &compile_unit, pool.interface());
    defer env.deinit();

    try env.installModule(lola.libs.std, lola.runtime.Context.init(std.mem.Allocator, allocator));
    try env.installModule(lola.libs.runtime, lola.runtime.Context.init(std.mem.Allocator, allocator));

    var vm = try lola.runtime.VM.init(allocator, &env);
    defer vm.deinit();

    var result = try vm.execute(405);
    std.debug.assert(result == .exhausted); // we didn't finish running our nice example

    var stdout = std.io.getStdOut().writer();
    try stdout.writeAll("Suspend at\n");
    try vm.printStackTrace(stdout);

    {
        var stream = std.io.fixedBufferStream(serialization_buffer);
        var writer = stream.writer();

        try compile_unit.saveToStream(writer);

        // This saves all objects associated with their handles.
        // This will only work when all object classes are serializable though.
        try pool.serialize(writer);

        // this saves all global variables saved in the environment
        try env.serialize(writer);

        var registry = lola.runtime.EnvironmentMap.init(allocator);
        defer registry.deinit();

        try registry.add(1234, &env);

        // This saves the current virtual machine state
        try vm.serialize(&registry, writer);

        try stdout.print("saved state to {} bytes!\n", .{
            stream.getWritten().len,
        });
    }
}

fn run_deserialization(allocator: *std.mem.Allocator, serialization_buffer: []u8) !void {
    var stream = std.io.fixedBufferStream(serialization_buffer);
    var reader = stream.reader();

    // Trivial deserialization:
    // Just load the compile unit from disk again
    var compile_unit = try lola.CompileUnit.loadFromStream(allocator, reader);
    defer compile_unit.deinit();

    // This is the reason we need to specialize lola.runtime.ObjectPool() on
    // a type list:
    // We need a way to do generic deserialization (arbitrary types) and it requires
    // a way to get a runtime type-handle and turn it back into a deserialization function.
    // this is done by storing the type indices per created object which can then be turned back
    // into a real lola.runtime.Object.
    var object_pool = try ObjectPool.deserialize(allocator, reader);
    defer object_pool.deinit();

    // Environments cannot be deserialized directly from a stream:
    // Each environment contains function pointers and references its compile unit.
    // Both of these things cannot be done by a pure stream serialization.
    // Thus, we need to restore the constant part of the environment by hand and
    // install all functions as well:
    var env = try lola.runtime.Environment.init(allocator, &compile_unit, object_pool.interface());
    defer env.deinit();

    // Installs the functions back into the environment.
    try lola.libs.std.install(&env, allocator);
    try lola.libs.runtime.install(&env, allocator);

    // This will restore the whole environment state back to how it was at serialization
    // time. All globals will be restored here.
    try env.deserialize(reader);

    // This is needed for deserialization:
    // We need means to have a unique Environment <-> ID mapping
    // which is persistent over the serialization process.
    var registry = lola.runtime.EnvironmentMap.init(allocator);
    defer registry.deinit();

    // Here we need to add all environments that were previously serialized with
    // the same IDs as before.
    try registry.add(1234, &env);

    // Restore the virtual machine with all function calls.
    var vm = try lola.runtime.VM.deserialize(allocator, &registry, reader);
    defer vm.deinit();

    var stdout = std.io.getStdOut().writer();
    try stdout.print("restored state with {} bytes!\n", .{
        stream.getWritten().len,
    });

    try stdout.writeAll("Resume at\n");
    try vm.printStackTrace(stdout);

    // let the program finish
    _ = try vm.execute(null);
}
