const std = @import("../std.zig");
const mem = std.mem;

var backing_buf = NullAllocator{};

pub const allocator = &backing_buf;

/// Allocator that always fails to allocate any memory.
/// This is the allocator that can be used to buffer
/// literal values.
pub const NullAllocator = struct {
    fn realloc(allocator: *mem.Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) ![]u8 {
        if (new_size != 0)
            return error.OutOfMemory;
        return &[0]u8{};
    }

    fn shrink(allocator: *mem.Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) []u8 {
        return old_mem[0..new_size];
    }
};
