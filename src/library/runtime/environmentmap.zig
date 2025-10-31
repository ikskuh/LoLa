const std = @import("std");
const lola = @import("../main.zig");

/// This map is required by the VM serialization to identify environment pointers
/// and allow serialization/deserialization of the correct references.
pub const EnvironmentMap = struct {
    const Self = @This();

    const Entry = struct {
        env: *lola.runtime.Environment,
        id: u32,
    };

    items: std.ArrayList(Entry),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .items = std.ArrayList(Entry).empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit(self.allocator);
        self.* = undefined;
    }

    /// Adds a new environment-id-pair to the map.
    /// Will return `error.IdAlreadyMapped` if a environment with this ID already exists,
    /// will return `error.EnvironmentAlreadyMapped` if the given environment is already in the map.
    /// Will return `error.OutOfMemory` when the internal storage cannot be resized.
    pub fn add(self: *Self, id: u32, env: *lola.runtime.Environment) !void {
        for (self.items.items) |item| {
            if (item.id == id)
                return error.IdAlreadyMapped;
            if (item.env == env)
                return error.EnvironmentAlreadyMapped;
        }
        try self.items.append(self.allocator, Entry{
            .id = id,
            .env = env,
        });
    }

    /// Returns the ID for the given environment or `null` if the environment was not registered.
    pub fn queryByPtr(self: Self, env: *lola.runtime.Environment) ?u32 {
        return for (self.items.items) |item| {
            if (item.env == env)
                break item.id;
        } else null;
    }

    /// Returns the Environment for the given id or `null` if the environment was not registered.
    pub fn queryById(self: Self, id: u32) ?*lola.runtime.Environment {
        return for (self.items.items) |item| {
            if (item.id == id)
                break item.env;
        } else null;
    }
};

test "EnvironmentMap" {
    // three storage locations
    var env_1: lola.runtime.Environment = undefined;
    var env_2: lola.runtime.Environment = undefined;
    var env_3: lola.runtime.Environment = undefined;

    var map = EnvironmentMap.init(std.testing.allocator);
    defer map.deinit();

    try map.add(1, &env_1);
    try map.add(2, &env_2);

    try std.testing.expectEqual(@as(?*lola.runtime.Environment, &env_1), map.queryById(1));
    try std.testing.expectEqual(@as(?*lola.runtime.Environment, &env_2), map.queryById(2));
    try std.testing.expectEqual(@as(?*lola.runtime.Environment, null), map.queryById(3));

    try std.testing.expectEqual(@as(?u32, 1), map.queryByPtr(&env_1));
    try std.testing.expectEqual(@as(?u32, 2), map.queryByPtr(&env_2));
    try std.testing.expectEqual(@as(?u32, null), map.queryByPtr(&env_3));
}
