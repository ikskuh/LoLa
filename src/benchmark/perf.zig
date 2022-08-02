//! This tool measures LoLa performance by running a set of different benchmark files

const std = @import("std");
const builtin = @import("builtin");
const lola = @import("lola");

// This is required for the runtime library to be able to provide
// object implementations.
pub const ObjectPool = lola.runtime.ObjectPool([_]type{
    lola.libs.runtime.LoLaDictionary,
    lola.libs.runtime.LoLaList,
});

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const argv = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), argv);

    if (argv.len != 3) {
        return 1;
    }

    const date_time = std.time.epoch.EpochSeconds{
        .secs = @intCast(u64, std.time.timestamp()),
    };
    const time = date_time.getDaySeconds();
    const date = date_time.getEpochDay();
    const year_day = date.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    var files = std.ArrayList(Benchmark).init(gpa.allocator());
    defer files.deinit();

    var string_arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer string_arena.deinit();

    const date_string = try std.fmt.allocPrint(string_arena.allocator(), "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index,
        time.getHoursIntoDay(),
        time.getMinutesIntoHour(),
        time.getSecondsIntoMinute(),
    });

    {
        var dir = try std.fs.cwd().openIterableDir(argv[1], .{});
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const name = try string_arena.allocator().dupe(u8, entry.name);
            const source = try dir.dir.readFileAlloc(string_arena.allocator(), entry.name, size(1.5, .MeBi)); // 1 MB source

            const target_file = try std.fmt.allocPrint(string_arena.allocator(), "{s}-{s}.csv", .{
                name[0 .. name.len - std.fs.path.extension(name).len],
                @tagName(builtin.mode),
            });

            try files.append(Benchmark{
                .file_name = name,
                .source_code = source,
                .target_file = target_file,
            });
        }
    }

    var output_dir = try std.fs.cwd().openDir(argv[2], .{});
    defer output_dir.close();

    for (files.items) |benchmark| {
        const result = benchmark.run(gpa.allocator()) catch |err| {
            std.log.warn("failed to run benchmark {s}: {s}", .{
                benchmark.file_name,
                @errorName(err),
            });
            continue;
        };

        var file: std.fs.File = if (output_dir.openFile(benchmark.target_file, .{ .mode = .write_only })) |file|
            file
        else |_| blk: {
            var file = try output_dir.createFile(benchmark.target_file, .{});
            try file.writeAll("time;compile;setup;run\n");
            break :blk file;
        };
        defer file.close();

        try file.seekFromEnd(0);

        try file.writer().print("{s};{d};{d};{d}\n", .{ date_string, result.compile_time, result.setup_time, result.run_time });
    }

    return 0;
}

pub const Unit = enum(u64) {
    base = 1,

    kilo = 1000,
    KiBi = 1024,

    mega = 1000 * 1000,
    MeBi = 1024 * 1024,

    giga = 1000 * 1000 * 1000,
    GiBi = 1024 * 1024 * 1024,

    tera = 1000 * 1000 * 1000 * 1000,
    TeBi = 1024 * 1024 * 1024 * 1024,
};
pub fn size(comptime val: comptime_float, comptime unit: Unit) usize {
    return @floatToInt(usize, std.math.floor(@as(f64, @as(comptime_int, @enumToInt(unit)) * val)));
}

pub const BenchmarkResult = struct {
    build_mode: std.builtin.Mode = builtin.mode,
    compile_time: u128,
    setup_time: u128,
    run_time: u128,
};

const Benchmark = struct {
    file_name: []const u8,
    source_code: []const u8,
    target_file: []const u8,

    pub fn run(self: Benchmark, allocator: std.mem.Allocator) !BenchmarkResult {
        std.log.info("Running benchmark {s}...", .{self.file_name});

        var result = BenchmarkResult{
            .compile_time = undefined,
            .setup_time = undefined,
            .run_time = undefined,
        };

        const compile_start = std.time.nanoTimestamp();

        var diagnostics = lola.compiler.Diagnostics.init(allocator);
        defer {
            for (diagnostics.messages.items) |msg| {
                std.debug.print("{}\n", .{msg});
            }
            diagnostics.deinit();
        }

        // This compiles a piece of source code into a compile unit.
        // A compile unit is a piece of LoLa IR code with metadata for
        // all existing functions, debug symbols and so on. It can be loaded into
        // a environment and be executed.
        var compile_unit = (try lola.compiler.compile(allocator, &diagnostics, self.file_name, self.source_code)) orelse return error.SyntaxError;
        defer compile_unit.deinit();

        const setup_start = std.time.nanoTimestamp();
        result.compile_time = @intCast(u128, setup_start - compile_start);

        var pool = ObjectPool.init(allocator);
        defer pool.deinit();

        var env = try lola.runtime.Environment.init(allocator, &compile_unit, pool.interface());
        defer env.deinit();

        try env.installModule(lola.libs.std, lola.runtime.Context.null_pointer);
        try env.installModule(lola.libs.runtime, lola.runtime.Context.null_pointer);

        var vm = try lola.runtime.VM.init(allocator, &env);
        defer vm.deinit();

        const runtime_start = std.time.nanoTimestamp();
        result.setup_time = @intCast(u128, runtime_start - setup_start);

        while (true) {
            var res = try vm.execute(1_000_000);

            pool.clearUsageCounters();
            try pool.walkEnvironment(env);
            try pool.walkVM(vm);
            pool.collectGarbage();

            if (res == .completed)
                break;
        }

        result.run_time = @intCast(u128, std.time.nanoTimestamp() - runtime_start);

        return result;
    }
};
