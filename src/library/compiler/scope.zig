const std = @import("std");

const Type = @import("typeset.zig").Type;
const TypeSet = @import("typeset.zig").TypeSet;

/// A scope structure that can be used to manage variable
/// allocation with different scopes (global, local).
pub const Scope = struct {
    const Self = @This();

    const Variable = struct {
        /// This is the offset of the variables
        name: []const u8,
        storage_slot: u16,
        type: enum { local, global },
        possible_types: TypeSet = TypeSet.any,
        is_const: bool,
    };

    arena: std.heap.ArenaAllocator,
    local_variables: std.ArrayList(Variable),
    global_variables: std.ArrayList(Variable),
    return_point: std.ArrayList(usize),

    /// When this is true, the scope will declare
    /// top-level variables as `global`, otherwise as `local`.
    is_global: bool,

    /// When this is non-null, the scope will use this as a fallback
    /// in `get` and will pass the query to this value.
    /// Note: It is not allowed that `global_scope` will return a `local` variable then!
    global_scope: ?*Self,

    /// The highest number of local variables that were declared at a point in this scope.
    max_locals: usize = 0,

    allocator: std.mem.Allocator,

    /// Creates a new scope.
    /// `global_scope` is a reference towards a scope that will provide references to a encasing scope.
    /// This scope must only provide `global` variables.
    pub fn init(allocator: std.mem.Allocator, global_scope: ?*Self, is_global: bool) Self {
        return Self{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .local_variables = std.ArrayList(Variable).empty,
            .global_variables = std.ArrayList(Variable).empty,
            .return_point = std.ArrayList(usize).empty,
            .is_global = is_global,
            .global_scope = global_scope,
        };
    }

    pub fn deinit(self: *Self) void {
        self.local_variables.deinit(self.allocator);
        self.global_variables.deinit(self.allocator);
        self.return_point.deinit(self.allocator);
        self.arena.deinit();
        self.* = undefined;
    }

    /// Enters a sub-scope. This is usually called at the start of a block.
    /// Sub-scopes are a set of variables that are only valid in a smaller
    /// portion of the code.
    /// This will push a return point to which later must be returned by
    /// calling `leave`.
    pub fn enter(self: *Self) !void {
        try self.return_point.append(self.allocator, self.local_variables.items.len);
    }

    /// Leaves a sub-scope. This is usually called at the end of a block.
    pub fn leave(self: *Self) !void {
        self.local_variables.shrinkRetainingCapacity(self.return_point.pop().?);
    }

    /// Declares are new variable.
    pub fn declare(self: *Self, name: []const u8, is_const: bool) !void {
        if (self.is_global and (self.return_point.items.len == 0)) {
            // a variable is only global when the scope is a global scope and
            // we don't have any sub-scopes open (which would create temporary variables)
            for (self.global_variables.items) |variable| {
                if (std.mem.eql(u8, variable.name, name)) {
                    // Global variables are not allowed to
                    return error.AlreadyDeclared;
                }
            }

            if (self.global_variables.items.len == std.math.maxInt(u16))
                return error.TooManyVariables;
            try self.global_variables.append(self.allocator, Variable{
                .storage_slot = @as(u16, @intCast(self.global_variables.items.len)),
                .name = try self.arena.allocator().dupe(u8, name),
                .type = .global,
                .is_const = is_const,
            });
        } else {
            if (self.local_variables.items.len == std.math.maxInt(u16))
                return error.TooManyVariables;
            try self.local_variables.append(self.allocator, Variable{
                .storage_slot = @as(u16, @intCast(self.local_variables.items.len)),
                .name = try self.arena.allocator().dupe(u8, name),
                .type = .local,
                .is_const = is_const,
            });

            self.max_locals = @max(self.max_locals, self.local_variables.items.len);
        }
    }

    /// Tries to return a variable named `name`. This will first search in the
    /// local variables, then in the global ones.
    /// Will return `null` when a variable is not found.
    pub fn get(self: Self, name: []const u8) ?*Variable {
        var i: usize = undefined;

        // First, search all local variables back-to-front:
        // This allows trivial shadowing as variables will be searched
        // in reverse declaration order.
        i = self.local_variables.items.len;
        while (i > 0) {
            i -= 1;
            const variable = &self.local_variables.items[i];
            if (std.mem.eql(u8, variable.name, name))
                return variable;
        }

        if (self.is_global) {
            // The same goes for global variables
            i = self.global_variables.items.len;
            while (i > 0) {
                i -= 1;
                const variable = &self.global_variables.items[i];
                if (std.mem.eql(u8, variable.name, name))
                    return variable;
            }
        }

        if (self.global_scope) |globals| {
            const global = globals.get(name);

            // The global scope is not allowed to supply local variables to us. If this happens,
            // a programming error was done.
            std.debug.assert(global == null or global.?.type != .local);

            return global;
        }

        return null;
    }
};

test "scope init/deinit" {
    var scope = Scope.init(std.testing.allocator, null, false);
    defer scope.deinit();
}

test "scope declare/get" {
    var scope = Scope.init(std.testing.allocator, null, true);
    defer scope.deinit();

    try scope.declare("foo", true);

    try std.testing.expectError(error.AlreadyDeclared, scope.declare("foo", true));

    try scope.enter();

    try scope.declare("bar", true);

    try std.testing.expect(scope.get("foo").?.type == .global);
    try std.testing.expect(scope.get("bar").?.type == .local);
    try std.testing.expect(scope.get("bam") == null);

    try scope.leave();

    try std.testing.expect(scope.get("foo").?.type == .global);
    try std.testing.expect(scope.get("bar") == null);
    try std.testing.expect(scope.get("bam") == null);
}

test "variable allocation" {
    var scope = Scope.init(std.testing.allocator, null, true);
    defer scope.deinit();

    try scope.declare("foo", true);
    try scope.declare("bar", true);
    try scope.declare("bam", true);

    try std.testing.expect(scope.get("foo").?.storage_slot == 0);
    try std.testing.expect(scope.get("bar").?.storage_slot == 1);
    try std.testing.expect(scope.get("bam").?.storage_slot == 2);

    try scope.enter();

    try scope.declare("foo", true);

    try scope.enter();

    try scope.declare("bar", true);
    try scope.declare("bam", true);

    try std.testing.expect(scope.get("foo").?.storage_slot == 0);
    try std.testing.expect(scope.get("bar").?.storage_slot == 1);
    try std.testing.expect(scope.get("bam").?.storage_slot == 2);

    try std.testing.expect(scope.get("foo").?.type == .local);
    try std.testing.expect(scope.get("bar").?.type == .local);
    try std.testing.expect(scope.get("bam").?.type == .local);

    try scope.leave();

    try std.testing.expect(scope.get("foo").?.type == .local);
    try std.testing.expect(scope.get("bar").?.type == .global);
    try std.testing.expect(scope.get("bam").?.type == .global);

    try scope.leave();

    try std.testing.expect(scope.get("foo").?.type == .global);
    try std.testing.expect(scope.get("bar").?.type == .global);
    try std.testing.expect(scope.get("bam").?.type == .global);
}
