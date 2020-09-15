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

// this will store our intermediate data
var serialization_buffer: [4096]u8 = undefined;

pub fn main() anyerror!void {
    {
        var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa_state.deinit();

        try run_serialization(&gpa_state.allocator);
    }

    {
        var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa_state.deinit();

        try run_deserialization(&gpa_state.allocator);
    }
}

fn run_serialization(allocator: *std.mem.Allocator) !void {
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

    try lola.libs.std.install(&env, allocator);
    try lola.libs.runtime.install(&env, allocator);

    var vm = try lola.runtime.VM.init(allocator, &env);
    defer vm.deinit();

    var result = try vm.execute(405);
    std.debug.assert(result == .exhausted); // we didn't finish running our nice example

    var stdout = std.io.getStdOut().writer();

    try stdout.writeAll("Suspend at\n");
    try vm.printStackTrace(stdout);

    {
        var stream = std.io.fixedBufferStream(&serialization_buffer);
        var writer = stream.writer();

        try compile_unit.saveToStream(writer);

        // This saves all objects associated with their handles.
        // This will only work when all object classes are serializable though.
        try pool.serialize(writer);

        // this saves all global variables saved in the environment
        // TODO: try env.serialize(writer);

        // This saves the current virtual machine state
        // TODO: try vm.serialize(writer);

        std.debug.print("saved state to {} bytes!\n", .{
            stream.getWritten().len,
        });
    }
}

fn run_deserialization(allocator: *std.mem.Allocator) !void {
    unreachable;
}
