const std = @import("std");
const lola = @import("lola");

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);

    var file = try std.fs.cwd().openFile("../Example/hello-world.lm", .{ .read = true, .write = false });
    defer file.close();

    var stream = file.inStream();
    var cu = try lola.CompileUnit.loadFromStream(&arena.allocator, std.fs.File.InStream.Error, &stream.stream);
    defer cu.deinit();

    var decoder = lola.Decoder.init(cu.code);

    while (!decoder.isEof()) {
        const instr = try decoder.read(lola.Instruction);
        switch (instr) {
            .push_str, .store_global_name, .load_global_name => {
                const str = try decoder.readVarString();
                std.debug.warn("{} \"{}\"\n", .{ @tagName(instr), str });
            },
            .call_fn, .call_obj => {
                const str = try decoder.readVarString();
                const argc = try decoder.read(u8);
                std.debug.warn("{} \"{}\" {}\n", .{ @tagName(instr), str, argc });
            },
            .jmp, .jnf, .jif => {
                const dest = try decoder.read(u32);
                std.debug.warn("{} {}\n", .{ @tagName(instr), dest });
            },
            .store_local, .load_local, .store_global_idx, .load_global_idx => {
                const dest = try decoder.read(u16);
                std.debug.warn("{} {}\n", .{ @tagName(instr), dest });
            },
            else => {
                std.debug.warn("{}\n", .{@tagName(instr)});
            },
        }
    }
}
