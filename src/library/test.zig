// this path is mainly to provide a neat test environment

const lola = @import("main.zig");

comptime {
    _ = lola;
}

pub const ObjectPool = lola.runtime.ObjectPool(.{});
