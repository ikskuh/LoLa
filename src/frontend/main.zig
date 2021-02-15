const std = @import("std");
const lola = @import("lola");
const argsParser = @import("args");
const build_options = @import("build_options");

var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = &gpa_state.allocator;

// This is our global object pool that is back-referenced
// by the runtime library.
pub const ObjectPool = lola.runtime.ObjectPool([_]type{
    lola.libs.runtime.LoLaList,
    lola.libs.runtime.LoLaDictionary,
});

pub fn main() !u8 {
    defer _ = gpa_state.deinit();

    var args = std.process.args();

    var argsAllocator = gpa;

    const exeName = try (args.next(argsAllocator) orelse {
        try std.io.getStdErr().writer().writeAll("Failed to get executable name from the argument list!\n");
        return 1;
    });
    defer argsAllocator.free(exeName);

    const module = try (args.next(argsAllocator) orelse {
        try print_usage();
        return 1;
    });
    defer argsAllocator.free(module);

    if (std.mem.eql(u8, module, "compile")) {
        const options = try argsParser.parse(CompileCLI, &args, argsAllocator);
        defer options.deinit();

        return try compile(options.options, options.positionals);
    } else if (std.mem.eql(u8, module, "dump")) {
        const options = try argsParser.parse(DisassemblerCLI, &args, argsAllocator);
        defer options.deinit();

        return try disassemble(options.options, options.positionals);
    } else if (std.mem.eql(u8, module, "run")) {
        const options = try argsParser.parse(RunCLI, &args, argsAllocator);
        defer options.deinit();

        return try run(options.options, options.positionals);
    } else if (std.mem.eql(u8, module, "help")) {
        try print_usage();
        return 0;
    } else if (std.mem.eql(u8, module, "version")) {
        try std.io.getStdOut().writeAll(build_options.version ++ "\n");
        return 0;
    } else {
        try std.io.getStdErr().writer().print(
            "Unrecognized command: {s}\nSee `lola help` for detailed usage information.\n",
            .{
                module,
            },
        );
        return 1;
    }

    return 0;
}

pub fn print_usage() !void {
    const usage_msg =
        \\Usage: lola [command] [options]
        \\
        \\Commands:
        \\  compile [source]                   Compiles the given source file into a module.
        \\  dump [module]                      Disassembles the given module.
        \\  run [file]                         Runs the given file. Both modules and source files are allowed.
        \\  version                            Prints version number and exits.
        \\
        \\General Options:
        \\  -o [output file]                   Defines the output file for the action.
        \\
        \\Compile Options:
        \\  --verify, -v                       Does not emit the output file, but only runs in-memory checks.
        \\                                     This can be used to do syntax checks of the code.
        \\
        \\Disassemble Options:
        \\  --with-offset, -O                  Adds offsets to the disassembly.
        \\  --with-hexdump, -b                 Adds the hex dump in the disassembly.
        \\  --metadata                         Dumps information about the module itself.
        \\
        \\Run Options:
        \\  --limit [n]                        Limits execution to [n] instructions, then halts.
        \\  --mode [autodetect|source|module]  Determines if run should interpret the file as a source file,
        \\                                     a precompiled module or if it should autodetect the file type.
        \\  --no-stdlib                        Removes the standard library from the environment.
        \\  --no-runtime                       Removes the system runtime from the environment.
        \\  --benchmark                        Runs the script 100 times, measuring the duration of each run and
        \\                                     will print a benchmark result in the end.
        \\
    ;
    // \\  -S                      Intermixes the disassembly with the original source code if possible.
    try std.io.getStdErr().writer().writeAll(usage_msg);
}

const DisassemblerCLI = struct {
    @"output": ?[]const u8 = null,
    @"metadata": bool = false,
    @"with-offset": bool = false,
    @"with-hexdump": bool = false,
    // @"intermix-source": bool = false,

    pub const shorthands = .{
        // .S = "intermix-source",
        .b = "with-hexdump",
        .O = "with-offset",
        .o = "output",
        .m = "metadata",
    };
};

fn disassemble(options: DisassemblerCLI, files: []const []const u8) !u8 {
    var stream = std.io.getStdOut().writer();

    if (files.len == 0) {
        try print_usage();
        return 1;
    }

    var logfile: ?std.fs.File = null;
    defer if (logfile) |f|
        f.close();

    if (options.output) |outfile| {
        logfile = try std.fs.cwd().createFile(outfile, .{
            .read = false,
            .truncate = true,
            .exclusive = false,
        });
        stream = logfile.?.writer();
    }

    for (files) |arg| {
        if (files.len != 1) {
            try stream.print("Disassembly for {s}:\n", .{arg});
        }

        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();

        const allocator = &arena.allocator;

        var cu = blk: {
            var file = try std.fs.cwd().openFile(arg, .{ .read = true, .write = false });
            defer file.close();

            break :blk try lola.CompileUnit.loadFromStream(allocator, file.reader());
        };
        defer cu.deinit();

        if (options.metadata) {
            try stream.writeAll("metadata:\n");
            try stream.print("\tcomment:         {s}\n", .{cu.comment});
            try stream.print("\tcode size:       {d} bytes\n", .{cu.code.len});
            try stream.print("\tnum globals:     {d}\n", .{cu.globalCount});
            try stream.print("\tnum temporaries: {d}\n", .{cu.temporaryCount});
            try stream.print("\tnum functions:   {d}\n", .{cu.functions.len});
            for (cu.functions) |fun| {
                try stream.print("\t\tep={X:0>4}  lc={: >3}  {s}\n", .{
                    fun.entryPoint,
                    fun.localCount,
                    fun.name,
                });
            }
            try stream.print("\tnum debug syms:  {d}\n", .{cu.debugSymbols.len});

            try stream.writeAll("disassembly:\n");
        }

        try lola.disassemble(stream, cu, lola.DisassemblerOptions{
            .addressPrefix = options.@"with-offset",
            .hexwidth = if (options.@"with-hexdump") 8 else null,
            .labelOutput = true,
            .instructionOutput = true,
        });
    }

    return 0;
}

const CompileCLI = struct {
    @"output": ?[]const u8 = null,
    verify: bool = false,

    pub const shorthands = .{
        .o = "output",
        .v = "verify",
    };
};

const ModuleBuffer = extern struct {
    data: [*]u8,
    length: usize,
};

fn compile(options: CompileCLI, files: []const []const u8) !u8 {
    if (files.len != 1) {
        try print_usage();
        return 1;
    }

    const allocator = gpa;

    const inname = files[0];

    const outname = if (options.output) |name|
        name
    else blk: {
        var name = try allocator.alloc(u8, inname.len + 3);
        std.mem.copy(u8, name[0..inname.len], inname);
        std.mem.copy(u8, name[inname.len..], ".lm");
        break :blk name;
    };
    defer if (options.output == null)
        allocator.free(outname);

    const cu = compileFileToUnit(allocator, inname) catch |err| switch (err) {
        error.CompileError => return 1,
        else => |e| return e,
    };
    defer cu.deinit();

    if (!options.verify) {
        var file = try std.fs.cwd().createFile(outname, .{ .truncate = true, .read = false, .exclusive = false });
        defer file.close();

        try cu.saveToStream(file.writer());
    }

    return 0;
}

const RunCLI = struct {
    limit: ?u32 = null,
    mode: enum { autodetect, source, module } = .autodetect,
    @"no-stdlib": bool = false,
    @"no-runtime": bool = false,
    benchmark: bool = false,
};

fn autoLoadModule(allocator: *std.mem.Allocator, options: RunCLI, file: []const u8) !lola.CompileUnit {
    return switch (options.mode) {
        .autodetect => loadModuleFromFile(allocator, file) catch |err| if (err == error.InvalidFormat)
            try compileFileToUnit(allocator, file)
        else
            return err,
        .module => try loadModuleFromFile(allocator, file),
        .source => try compileFileToUnit(allocator, file),
    };
}

fn run(options: RunCLI, files: []const []const u8) !u8 {
    if (files.len != 1) {
        try print_usage();
        return 1;
    }

    const allocator = gpa;

    var cu = autoLoadModule(allocator, options, files[0]) catch |err| {
        const stderr = std.io.getStdErr().writer();

        if (err == error.FileNotFound) {
            try stderr.print("Could not find '{s}'. Are you sure you passed the right file?\n", .{files[0]});
            return 1;
        }

        try stderr.writeAll(switch (options.mode) {
            .autodetect => "Failed to run file: File seems not to be a compiled module or source file!\n",
            .module => "Failed to run file: File seems not to be a compiled module.\n",
            .source => return 1, // We already have the diagnostic output of the compiler anyways
        });
        if (err != error.InvalidFormat and err != error.CompileError) {
            try stderr.print("The following error happened: {s}\n", .{
                @errorName(err),
            });
        }
        return 1;
    };
    defer cu.deinit();

    var pool = ObjectPool.init(allocator);
    defer pool.deinit();

    var env = try lola.runtime.Environment.init(allocator, &cu, pool.interface());
    defer env.deinit();

    if (!options.@"no-stdlib") {
        try lola.libs.std.install(&env, allocator);
    }

    if (!options.@"no-runtime") {
        try lola.libs.runtime.install(&env, allocator);

        // Move these two to a test runner

        try env.installFunction("Expect", lola.runtime.Function.initSimpleUser(struct {
            fn call(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
                if (args.len != 1)
                    return error.InvalidArgs;
                const assertion = try args[0].toBoolean();

                if (!assertion)
                    return error.AssertionFailed;

                return .void;
            }
        }.call));

        try env.installFunction("ExpectEqual", lola.runtime.Function.initSimpleUser(struct {
            fn call(environment: *const lola.runtime.Environment, context: lola.runtime.Context, args: []const lola.runtime.Value) anyerror!lola.runtime.Value {
                if (args.len != 2)
                    return error.InvalidArgs;
                if (!args[0].eql(args[1])) {
                    std.log.err("Expected {}, got {}\n", .{ args[1], args[0] });
                    return error.AssertionFailed;
                }

                return .void;
            }
        }.call));
    }

    if (options.benchmark == false) {
        var vm = try lola.runtime.VM.init(allocator, &env);
        defer vm.deinit();

        while (true) {
            var result = vm.execute(options.limit) catch |err| {
                var stderr = std.io.getStdErr().writer();

                if (std.builtin.mode == .Debug) {
                    if (@errorReturnTrace()) |err_trace| {
                        std.debug.dumpStackTrace(err_trace.*);
                    } else {
                        try stderr.print("Panic during execution: {s}\n", .{@errorName(err)});
                    }
                } else {
                    try stderr.print("Panic during execution: {s}\n", .{@errorName(err)});
                }
                try stderr.print("Call stack:\n", .{});

                try vm.printStackTrace(stderr);

                return 1;
            };

            pool.clearUsageCounters();

            try pool.walkEnvironment(env);
            try pool.walkVM(vm);

            pool.collectGarbage();

            switch (result) {
                .completed => return 0,
                .exhausted => {
                    try std.io.getStdErr().writer().print("Execution exhausted after {d} instructions!\n", .{
                        options.limit,
                    });
                    return 1;
                },
                .paused => {
                    // continue execution here
                    std.time.sleep(100); // sleep at least 100 ns and return control to scheduler
                },
            }
        }
    } else {
        var cycle: usize = 0;
        var stats = lola.runtime.VM.Statistics{};
        var total_time: u64 = 0;

        var total_timer = try std.time.Timer.start();

        // Run at least one second
        while ((cycle < 100) or (total_timer.read() < std.time.ns_per_s)) : (cycle += 1) {
            var vm = try lola.runtime.VM.init(allocator, &env);
            defer vm.deinit();

            var timer = try std.time.Timer.start();

            emulation: while (true) {
                var result = vm.execute(options.limit) catch |err| {
                    var stderr = std.io.getStdErr().writer();
                    try stderr.print("Panic during execution: {s}\n", .{@errorName(err)});
                    try stderr.print("Call stack:\n", .{});

                    try vm.printStackTrace(stderr);

                    return 1;
                };

                pool.clearUsageCounters();

                try pool.walkEnvironment(env);
                try pool.walkVM(vm);

                pool.collectGarbage();

                switch (result) {
                    .completed => break :emulation,
                    .exhausted => {
                        try std.io.getStdErr().writer().print("Execution exhausted after {d} instructions!\n", .{
                            options.limit,
                        });
                        return 1;
                    },
                    .paused => {},
                }
            }

            total_time += timer.lap();

            stats.instructions += vm.stats.instructions;
            stats.stalls += vm.stats.stalls;
        }

        try std.io.getStdErr().writer().print(
            \\Benchmark result:
            \\    Number of runs:     {d}
            \\    Mean time:          {d} µs
            \\    Mean #instructions: {d}
            \\    Mean #stalls:       {d}
            \\    Mean instruction/s: {d}
            \\
        , .{
            cycle,
            (@intToFloat(f64, total_time) / @intToFloat(f64, cycle)) / std.time.ns_per_us,
            @intToFloat(f64, stats.instructions) / @intToFloat(f64, cycle),
            @intToFloat(f64, stats.stalls) / @intToFloat(f64, cycle),
            std.time.ns_per_s * @intToFloat(f64, stats.instructions) / @intToFloat(f64, total_time),
        });
    }

    return 0;
}

fn compileFileToUnit(allocator: *std.mem.Allocator, fileName: []const u8) !lola.CompileUnit {
    const maxLength = 1 << 20; // 1 MB
    var source = blk: {
        var file = try std.fs.cwd().openFile(fileName, .{ .read = true, .write = false });
        defer file.close();

        break :blk try file.reader().readAllAlloc(gpa, maxLength);
    };
    defer gpa.free(source);

    var diag = lola.compiler.Diagnostics.init(allocator);
    defer {
        for (diag.messages.items) |msg| {
            std.debug.print("{}\n", .{msg});
        }
        diag.deinit();
    }

    const seq = try lola.compiler.tokenizer.tokenize(allocator, &diag, fileName, source);
    defer allocator.free(seq);

    var pgm = try lola.compiler.parser.parse(allocator, &diag, seq);
    defer pgm.deinit();

    const successful = try lola.compiler.validate(allocator, &diag, pgm);

    if (!successful)
        return error.CompileError;

    var compile_unit = try lola.compiler.generateIR(allocator, pgm, fileName);
    errdefer compile_unit;

    return compile_unit;
}

fn loadModuleFromFile(allocator: *std.mem.Allocator, fileName: []const u8) !lola.CompileUnit {
    var file = try std.fs.cwd().openFile(fileName, .{ .read = true, .write = false });
    defer file.close();

    return try lola.CompileUnit.loadFromStream(allocator, file.reader());
}
