const std = @import("std");

const utility = @import("utility.zig");

// Import modules to reduce file size
usingnamespace @import("value.zig");
usingnamespace @import("ir.zig");
usingnamespace @import("compile_unit.zig");
usingnamespace @import("decoder.zig");
usingnamespace @import("named_global.zig");

/// An execution environment provides all needed
/// data to execute a compiled piece of code.
/// It stores its global variables, available functions
/// and available features.
pub const Environment = struct {

    // /// A script function contained in either this or a foreign
    // /// environment. For foreign environments.
    // pub const ScriptFunction = struct {
    //     compileUnit: *const CompileUnit,
    //     entry_point: u32,
    //     local_count: u16,
    // };

    // pub const UserError = error{GenericError};

    // pub const UserFunction = fn (args: []const Value) UserError!Value;

    // pub const AsyncUserFunction = struct {
    //     // TODO: Implement async functions
    // };

    // pub const Function = union(enum) {
    //     script: ScriptFunction,
    //     syncUser: UserFunction,
    //     asyncUser: AsyncUserFunction,
    // };
    compileUnit: *const CompileUnit,
    scriptGlobals: []Value,

    namedGlobals: std.AutoHashMap([]const u8, NamedGlobal),

    functions: std.AutoHashMap([]const u8, Function),
};
