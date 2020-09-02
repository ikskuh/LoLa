const std = @import("std");

/// A scope structure that can be used to manage variable
/// allocation with different scopes (global, extern, local).
pub const Scope = struct {
    const Self = @This();

    const Variable = struct {
        /// This is the offset of the variables
        storage_slot: u16,
        type: enum { local, global, @"extern" },
    };

    arena: std.heap.ArenaAllocator,
    extern_variables: std.ArrayList([]const u8),
    local_variables: std.ArrayList([]const u8),
    global_variables: std.ArrayList([]const u8),
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

    /// Creates a new scope.
    /// `global_scope` is a reference towards a scope that will provide references to a encasing scope.
    /// This scope must only provide `global` or `extern` variables.
    pub fn init(allocator: *std.mem.Allocator, global_scope: ?*Self, is_global: bool) Self {
        return Self{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .extern_variables = std.ArrayList([]const u8).init(allocator),
            .local_variables = std.ArrayList([]const u8).init(allocator),
            .global_variables = std.ArrayList([]const u8).init(allocator),
            .return_point = std.ArrayList(usize).init(allocator),
            .is_global = is_global,
            .global_scope = global_scope,
        };
    }

    pub fn deinit(self: *Self) void {
        self.extern_variables.deinit();
        self.local_variables.deinit();
        self.global_variables.deinit();
        self.return_point.deinit();
        self.arena.deinit();
        self.* = undefined;
    }

    /// Enters a sub-scope. This is usually called at the start of a block.
    /// Sub-scopes are a set of variables that are only valid in a smaller
    /// portion of the code.
    /// This will push a return point to which later must be returned by
    /// calling `leave`.
    pub fn enter(self: *Self) !void {
        try self.return_point.append(self.local_variables.items.len);
    }

    /// Leaves a sub-scope. This is usually called at the end of a block.
    pub fn leave(self: *Self) !void {
        self.local_variables.shrink(self.return_point.pop());
    }

    /// Declares are new variable. Depending on the state of the scope,
    /// it will either be a global or a local variable, but will never be a
    /// extern variable.
    pub fn declare(self: *Self, name: []const u8) !void {
        if (self.is_global and (self.return_point.items.len == 0)) {
            // a variable is only global when the scope is a global scope and
            // we don't have any sub-scopes open (which would create temporary variables)
            for (self.global_variables.items) |varname| {
                if (std.mem.eql(u8, varname, name)) {
                    // Global variables are not allowed to
                    return error.AlreadyDeclared;
                }
            }

            if (self.global_variables.items.len == std.math.maxInt(u16))
                return error.TooManyVariables;
            try self.global_variables.append(try self.arena.allocator.dupe(u8, name));
        } else {
            if (self.local_variables.items.len == std.math.maxInt(u16))
                return error.TooManyVariables;
            try self.local_variables.append(try self.arena.allocator.dupe(u8, name));

            self.max_locals = std.math.max(self.max_locals, self.local_variables.items.len);
        }
    }

    /// Declares a extern variable
    pub fn declareExtern(self: *Self, name: []const u8) !void {
        // Search if an extern with this name was already declared:
        // If so, we're done
        for (self.extern_variables.items) |varname| {
            if (std.mem.eql(u8, varname, name))
                return;
        }

        if (self.extern_variables.items.len == std.math.maxInt(u16))
            return error.TooManyVariables;
        try self.extern_variables.append(try self.arena.allocator.dupe(u8, name));
    }

    /// Tries to return a variable named `name`. This will first search in the
    /// local variables, then in the global ones and then in extern variables.
    /// Will return `null` when a variable is not found.
    pub fn get(self: Self, name: []const u8) ?Variable {
        var i: usize = undefined;

        // First, search all local variables back-to-front:
        // This allows trivial shadowing as variables will be searched
        // in reverse declaration order.
        i = self.local_variables.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.local_variables.items[i], name))
                return Variable{ .type = .local, .storage_slot = @intCast(u16, i) };
        }

        if (self.is_global) {
            // The same goes for global variables
            i = self.global_variables.items.len;
            while (i > 0) {
                i -= 1;
                if (std.mem.eql(u8, self.global_variables.items[i], name))
                    return Variable{ .type = .global, .storage_slot = @intCast(u16, i) };
            }
        }

        // Extern variables don't have a defined order as they are referenced by-name and
        // don't have a storage slot assigned.
        for (self.extern_variables.items) |varname| {
            if (std.mem.eql(u8, varname, name))
                return Variable{ .type = .@"extern", .storage_slot = undefined };
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

    try scope.declareExtern("baz");

    try scope.declare("foo");

    std.testing.expectError(error.AlreadyDeclared, scope.declare("foo"));

    try scope.enter();

    try scope.declare("bar");

    std.testing.expect(scope.get("baz").?.type == .@"extern");
    std.testing.expect(scope.get("foo").?.type == .global);
    std.testing.expect(scope.get("bar").?.type == .local);
    std.testing.expect(scope.get("bam") == null);

    try scope.leave();

    std.testing.expect(scope.get("baz").?.type == .@"extern");
    std.testing.expect(scope.get("foo").?.type == .global);
    std.testing.expect(scope.get("bar") == null);
    std.testing.expect(scope.get("bam") == null);
}

test "variable allocation" {
    var scope = Scope.init(std.testing.allocator, null, true);
    defer scope.deinit();

    try scope.declare("foo");
    try scope.declare("bar");
    try scope.declare("bam");

    std.testing.expect(scope.get("foo").?.storage_slot == 0);
    std.testing.expect(scope.get("bar").?.storage_slot == 1);
    std.testing.expect(scope.get("bam").?.storage_slot == 2);

    try scope.enter();

    try scope.declare("foo");

    try scope.enter();

    try scope.declare("bar");
    try scope.declare("bam");

    std.testing.expect(scope.get("foo").?.storage_slot == 0);
    std.testing.expect(scope.get("bar").?.storage_slot == 1);
    std.testing.expect(scope.get("bam").?.storage_slot == 2);

    std.testing.expect(scope.get("foo").?.type == .local);
    std.testing.expect(scope.get("bar").?.type == .local);
    std.testing.expect(scope.get("bam").?.type == .local);

    try scope.leave();

    std.testing.expect(scope.get("foo").?.type == .local);
    std.testing.expect(scope.get("bar").?.type == .global);
    std.testing.expect(scope.get("bam").?.type == .global);

    try scope.leave();

    std.testing.expect(scope.get("foo").?.type == .global);
    std.testing.expect(scope.get("bar").?.type == .global);
    std.testing.expect(scope.get("bam").?.type == .global);
}
