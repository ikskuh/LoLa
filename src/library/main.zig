// Import all runtime namespaces
usingnamespace @import("common/ir.zig");
usingnamespace @import("common/compile-unit.zig");

usingnamespace @import("runtime/value.zig");
usingnamespace @import("runtime/decoder.zig");
usingnamespace @import("runtime/named_global.zig");
usingnamespace @import("runtime/disassembler.zig");
usingnamespace @import("runtime/environment.zig");
usingnamespace @import("runtime/vm.zig");
usingnamespace @import("runtime/context.zig");
usingnamespace @import("runtime/strings.zig");
usingnamespace @import("runtime/objects.zig");

// Export the stdlib as `lola.std`:
pub const std = @import("stdlib/main.zig");

pub const compiler = struct {
    pub const Diagnostics = @import("compiler/diagnostics.zig").Diagnostics;
    pub const tokenizer = @import("compiler/tokenizer.zig");
    pub const parser = @import("compiler/parser.zig");
    pub const ast = @import("compiler/ast.zig");

    pub const validate = @import("compiler/analysis.zig").validate;
    pub const generateIR = @import("compiler/codegen.zig").generateIR;
};

comptime {
    // include tests
    _ = @import("compiler/string-escaping.zig");
    _ = @import("compiler/diagnostics.zig");
    _ = @import("compiler/tokenizer.zig");
    _ = @import("compiler/parser.zig");
    _ = @import("compiler/ast.zig");
    _ = @import("compiler/code-writer.zig");
    _ = @import("compiler/analysis.zig");
    _ = @import("compiler/scope.zig");
    _ = @import("compiler/codegen.zig");
}
