const std = @import("std");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const argv = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, argv);

    if (argv.len != 3) {
        return 1;
    }

    var src_dir = try std.fs.cwd().openDir(argv[1], .{ .iterate = true });
    defer src_dir.close();

    var dst_dir = try std.fs.cwd().openDir(argv[2], .{});
    defer dst_dir.close();

    var data = std.ArrayList(Series).empty;

    {
        var iter = src_dir.iterate();
        while (try iter.next()) |entry| {
            if (!std.mem.eql(u8, std.fs.path.extension(entry.name), ".csv"))
                continue;

            const name_no_ext = entry.name[0 .. entry.name.len - 4];
            const idx = std.mem.lastIndexOfScalar(u8, name_no_ext, '-') orelse continue;

            var series = Series{
                .benchmark = try alloc.dupe(u8, name_no_ext[0..idx]),
                .mode = std.meta.stringToEnum(std.builtin.OptimizeMode, name_no_ext[idx + 1 ..]) orelse @panic("unexpected name"),
                .data = undefined,
            };

            var file = try src_dir.openFile(entry.name, .{ .mode = .read_only });
            defer file.close();

            series.data = try loadSeries(alloc, file);

            std.sort.block(DataPoint, series.data, {}, orderDataPoint);

            try data.append(alloc, series);
        }
    }

    try renderSeriesSet(dst_dir, "compile-ReleaseSafe.svg", data.items, "compile_time", filterReleaseSafe);
    try renderSeriesSet(dst_dir, "setup-ReleaseSafe.svg", data.items, "setup_time", filterReleaseSafe);
    try renderSeriesSet(dst_dir, "run-ReleaseSafe.svg", data.items, "run_time", filterReleaseSafe);

    try renderSeriesSet(dst_dir, "compile-ReleaseSmall.svg", data.items, "compile_time", filterReleaseSmall);
    try renderSeriesSet(dst_dir, "setup-ReleaseSmall.svg", data.items, "setup_time", filterReleaseSmall);
    try renderSeriesSet(dst_dir, "run-ReleaseSmall.svg", data.items, "run_time", filterReleaseSmall);

    try renderSeriesSet(dst_dir, "compile-ReleaseFast.svg", data.items, "compile_time", filterReleaseFast);
    try renderSeriesSet(dst_dir, "setup-ReleaseFast.svg", data.items, "setup_time", filterReleaseFast);
    try renderSeriesSet(dst_dir, "run-ReleaseFast.svg", data.items, "run_time", filterReleaseFast);

    return 0;
}

pub fn renderSeriesSet(dst_dir: std.fs.Dir, file_name: []const u8, all_series: []Series, comptime field: []const u8, comptime filter: fn (series: Series) bool) !void {
    var file = try dst_dir.createFile(file_name, .{});
    defer file.close();

    var writer_buffer: [4096]u8 = undefined;
    var file_writer = file.writer(&writer_buffer);
    const writer = &file_writer.interface;

    var start_time: u128 = std.math.maxInt(u128);
    var end_time: u128 = 0;
    var high: f32 = 0;

    const scale_base = 5;

    for (all_series) |series| {
        if (filter(series)) {
            start_time = @min(start_time, series.data[0].date.getLinearSortVal());
            end_time = @max(end_time, series.data[series.data.len - 1].date.getLinearSortVal());

            for (series.data) |dp| {
                high = @max(high, @as(f32, @floatFromInt(@field(dp, field))));
            }
        }
    }
    high = std.math.pow(f32, scale_base, @ceil(std.math.log(f32, scale_base, 1.3 * high)));

    const time_range = end_time - start_time;

    const size_x: f32 = 350;
    const size_y: f32 = 200;

    const legend_size: f32 = 50;

    const viewport_size: f32 = size_x - legend_size;

    try writer.print("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n", .{});
    try writer.print("<svg version=\"1.1\" viewBox=\"0 0 {d} {d}\" xmlns=\"http://www.w3.org/2000/svg\">\n", .{
        size_x,
        size_y,
    });

    const color_palette = [_][]const u8{
        "#442434",
        "#30346d",
        "#4e4a4e",
        "#854c30",
        "#346524",
        "#d04648",
        "#757161",
        "#597dce",
        "#d27d2c",
        "#8595a1",
        "#6daa2c",
        "#d2aa99",
        "#6dc2ca",
        "#dad45e",
    };

    var index: u32 = 0;
    for (all_series) |series| {
        if (filter(series)) {
            const color = color_palette[index % color_palette.len];

            try writer.print(
                \\  <text x="{d:.3}" y="{d:.3}" fill="{s}" font-family="sans-serif" font-size="5" xml:space="preserve">{s}</text>
                \\
            , .{
                viewport_size + 5,
                10 + 7 * index,
                color,
                series.benchmark,
            });

            try writer.print("  <path d=\"M", .{});

            for (series.data) |dp| {
                const dx = viewport_size * @as(f32, @floatFromInt(dp.date.getLinearSortVal() - start_time)) / @as(f32, @floatFromInt(time_range));
                const dy = size_y * (1.0 - @as(f32, @floatFromInt(@field(dp, field))) / high);

                try writer.print(" {d:.4} {d:.4}", .{ dx, dy });
            }

            try writer.print("\" fill=\"none\" stroke=\"{s}\" stroke-width=\"1.00\" />\n", .{
                color,
            });

            index += 1;
        }
    }
    try writer.print("</svg>\n", .{});
    try writer.flush();
}

fn filterReleaseSafe(series: Series) bool {
    return (series.mode == .ReleaseSafe);
}

fn filterReleaseSmall(series: Series) bool {
    return (series.mode == .ReleaseSmall);
}

fn filterReleaseFast(series: Series) bool {
    return (series.mode == .ReleaseFast);
}

fn orderDataPoint(_: void, lhs: DataPoint, rhs: DataPoint) bool {
    return lhs.date.getLinearSortVal() < rhs.date.getLinearSortVal();
}

pub const Date = struct {
    year: u32,
    day: u8,
    month: u8,

    hour: u8,
    minute: u8,
    second: u8,

    pub fn getLinearSortVal(date: Date) u64 {
        return 1 * @as(u64, date.second) +
            1_00 * @as(u64, date.minute) +
            1_00_00 * @as(u64, date.hour) +
            1_00_00_00 * @as(u64, date.month) +
            1_00_00_00_00 * @as(u64, date.day) +
            1_00_00_00_000 * @as(u64, date.year);
    }
};

pub const DataPoint = struct {
    date: Date,
    compile_time: u64,
    setup_time: u64,
    run_time: u64,
};

pub const Series = struct {
    benchmark: []const u8,
    mode: std.builtin.OptimizeMode,
    data: []DataPoint,
};

pub fn loadSeries(allocator: std.mem.Allocator, file: std.fs.File) ![]DataPoint {
    var line_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(&line_buffer);
    const reader = &file_reader.interface;

    const first_line = try reader.takeDelimiterExclusive('\n');

    if (!std.mem.eql(u8, first_line, "time;compile;setup;run"))
        return error.UnexpectedData;

    var data_set = std.ArrayList(DataPoint).empty;
    defer data_set.deinit(allocator);

    while (true) {
        const line_or_eof: ?[]u8 = reader.takeDelimiterExclusive('\n') catch null;
        if (line_or_eof) |line| {
            if (line.len == 0)
                continue;
            var iter = std.mem.splitScalar(u8, line, ';');
            const time_str = iter.next() orelse return error.UnexpectedData;
            const compile_str = try std.fmt.parseInt(u64, iter.next() orelse return error.UnexpectedData, 10);
            const setup_str = try std.fmt.parseInt(u64, iter.next() orelse return error.UnexpectedData, 10);
            const run_str = try std.fmt.parseInt(u64, iter.next() orelse return error.UnexpectedData, 10);

            if (time_str.len != 19) return error.UnexpectedData;

            try data_set.append(allocator, DataPoint{
                .date = Date{
                    // 2022-03-14 14:25:56
                    .year = try std.fmt.parseInt(u32, time_str[0..4], 10),
                    .day = try std.fmt.parseInt(u8, time_str[5..7], 10),
                    .month = try std.fmt.parseInt(u8, time_str[8..10], 10),
                    .hour = try std.fmt.parseInt(u8, time_str[11..13], 10),
                    .minute = try std.fmt.parseInt(u8, time_str[14..16], 10),
                    .second = try std.fmt.parseInt(u8, time_str[17..19], 10),
                },
                .compile_time = compile_str,
                .setup_time = setup_str,
                .run_time = run_str,
            });
        } else {
            break;
        }
    }

    return data_set.toOwnedSlice(allocator);
}
