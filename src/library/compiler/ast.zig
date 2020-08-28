const std = @import("std");

const Location = @import("location.zig").Location;

const UnaryOperator = enum {
    negate,
    boolean_not,
};

const BinaryOperator = enum {
    add,
    subtract,
    multiply,
    divide,
    modulus,
    boolean_or,
    boolean_and,
    less_than,
    greater_than,
    greater_or_equal_than,
    less_or_equal_than,
    equal,
    different,
};

const Expression = struct {
    /// Starting location of the statement
    location: Location,

    /// kind of the expression as well as associated child nodes.
    /// child expressions memory is stored in the `Program` structure.
    type: union(enum) {
        array_indexer: struct {
            value: *Expression,
            index: *Expression,
        },
        variable_expr: []const u8,
        array_literal: []Expression,
        function_call: struct {
            name: []const u8,
            arguments: []Expression,
        },
        method_call: struct {
            object: *Expression,
            name: []const u8,
            arguments: []Expression,
        },
        number_literal: f64,
        string_literal: []const u8,
        unary_operator: struct {
            operator: UnaryOperator,
            value: *Expression,
        },
        binary_operator: struct {
            operator: BinaryOperator,
            lhs: *Expression,
            rhs: *Expression,
        },
    },
};

const Statement = struct {
    /// Starting location of the statement
    location: Location,

    /// kind of the statement as well as associated child nodes.
    /// child statements and expressions memory is stored in the
    /// `Program` structure.
    type: union(enum) {
        assignment: struct {
            target: *Expression,
            value: *Expression,
        },
        return_void: void,
        return_expr: *Expression,
        while_loop: struct {
            condition: *Expression,
            body: *Statement,
        },
        for_loop: struct {
            variable: []const u8,
            source: *Expression,
            body: *Statement,
        },
        if_statement: struct {
            condition: *Expression,
            true_body: *Statement,
            false_body: ?*Statement,
        },
        discard_value: *Expression,
        declaration: struct {
            variable: []const u8,
            initial_value: ?*Expression,
        },
        extern_variable: []const u8,
        block: []Statement,
        @"break": void,
        @"continue": void,
    },
};

pub const Function = struct {
    name: []const u8,
    parameters: [][]const u8,
    body: Statement,
};

pub const Program = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator,
    root_script: []Statement,
    functions: []Function,

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }
};
