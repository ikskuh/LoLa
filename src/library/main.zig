const zig_std = @import("std");

// Import all runtime namespaces
pub usingnamespace @import("common/ir.zig");
pub usingnamespace @import("common/compile-unit.zig");

pub usingnamespace @import("common/disassembler.zig");
pub usingnamespace @import("common/decoder.zig");

/// Contains functions and structures for executing LoLa code.
pub const runtime = struct {
    usingnamespace @import("runtime/value.zig");
    usingnamespace @import("runtime/named_global.zig");
    usingnamespace @import("runtime/environment.zig");
    usingnamespace @import("runtime/vm.zig");
    usingnamespace @import("runtime/context.zig");
    usingnamespace @import("runtime/objects.zig");
};

/// LoLa libraries that provide pre-defined functions and variables.
pub const libs = @import("libraries/libs.zig");

/// Contains functions and structures to compile LoLa code.
pub const compiler = struct {
    pub const Diagnostics = @import("compiler/diagnostics.zig").Diagnostics;
    pub const Location = @import("compiler/location.zig").Location;
    pub const tokenizer = @import("compiler/tokenizer.zig");
    pub const parser = @import("compiler/parser.zig");
    pub const ast = @import("compiler/ast.zig");

    pub const validate = @import("compiler/analysis.zig").validate;
    pub const generateIR = @import("compiler/codegen.zig").generateIR;

    /// Compiles a LoLa source code into a CompileUnit.
    /// - `allocator` is used to perform all allocations in the compilation process.
    /// - `diagnostics` will contain all diagnostic messages after compilation.
    /// - `chunk_name` is the name of the source code piece. This is the name that will be used to refer to chunk in error messages, it is usually the file name.
    /// - `source_code` is the LoLa source code that should be compiled.
    /// The function returns either a compile unit when `source_code` is a valid program, otherwise it will return `null`.
    pub fn compile(
        allocator: *zig_std.mem.Allocator,
        diagnostics: *Diagnostics,
        chunk_name: []const u8,
        source_code: []const u8,
    ) !?CompileUnit {
        const seq = try tokenizer.tokenize(allocator, diagnostics, chunk_name, source_code);
        defer allocator.free(seq);

        var pgm = try parser.parse(allocator, diagnostics, seq);
        defer pgm.deinit();

        const valid_program = try validate(allocator, diagnostics, pgm);
        if (!valid_program)
            return null;

        return try generateIR(allocator, pgm, chunk_name);
    }
};

comptime {
    if (zig_std.builtin.is_test) {
        // include tests
        _ = @import("libraries/stdlib.zig");
        _ = @import("libraries/runtime.zig");
        _ = @import("compiler/diagnostics.zig");
        _ = @import("compiler/string-escaping.zig");
        _ = @import("compiler/codegen.zig");
        _ = @import("compiler/code-writer.zig");
        _ = @import("compiler/typeset.zig");
        _ = @import("compiler/analysis.zig");
        _ = @import("compiler/tokenizer.zig");
        _ = @import("compiler/parser.zig");
        _ = @import("compiler/location.zig");
        _ = @import("compiler/ast.zig");
        _ = @import("compiler/scope.zig");
        _ = @import("runtime/vm.zig");
        _ = @import("runtime/objects.zig");
        _ = @import("runtime/environment.zig");
        _ = @import("runtime/value.zig");
        _ = @import("runtime/context.zig");
        _ = @import("runtime/named_global.zig");
        _ = @import("common/decoder.zig");
        _ = @import("common/disassembler.zig");
        _ = @import("common/utility.zig");
        _ = @import("common/ir.zig");
        _ = @import("common/compile-unit.zig");
        _ = compiler.compile;

        _ = libs.runtime;
        _ = libs.std;
    }
}
