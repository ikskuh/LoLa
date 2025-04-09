const std = @import("std");
const assert = std.debug.assert;

const koino = @import("koino");

const MenuItem = struct {
    input_file_name: []const u8,
    output_file_name: []const u8,
    header: []const u8,
};

const menu_items = [_]MenuItem{
    MenuItem{
        .input_file_name = "documentation/README.md",
        .output_file_name = "website/docs/language.htm",
        .header = "Language Reference",
    },
    MenuItem{
        .input_file_name = "documentation/standard-library.md",
        .output_file_name = "website/docs/standard-library.htm",
        .header = "Standard Library",
    },
    MenuItem{
        .input_file_name = "documentation/runtime-library.md",
        .output_file_name = "website/docs/runtime-library.htm",
        .header = "Runtime Library",
    },
    MenuItem{
        .input_file_name = "documentation/ir.md",
        .output_file_name = "website/docs/intermediate-language.htm",
        .header = "IR",
    },
    MenuItem{
        .input_file_name = "documentation/modules.md",
        .output_file_name = "website/docs/module-binary.htm",
        .header = "Module Format",
    },
};

pub fn main() !u8 {
    @setEvalBranchQuota(1500);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    args.deinit();

    _ = args.next() orelse return 1; // exe name

    const version_name = args.next();

    for (menu_items, 0..) |current_file, current_index| {
        const options = koino.Options{
            .extensions = .{
                .table = true,
                .autolink = true,
                .strikethrough = true,
            },
        };

        var infile = try std.fs.cwd().openFile(current_file.input_file_name, .{});
        defer infile.close();

        const markdown = try infile.reader().readAllAlloc(allocator, 1024 * 1024 * 1024);
        defer allocator.free(markdown);

        const output = try markdownToHtml(allocator, options, markdown);
        defer allocator.free(output);

        var outfile = try std.fs.cwd().createFile(current_file.output_file_name, .{});
        defer outfile.close();

        try outfile.writeAll(
            \\<!DOCTYPE html>
            \\<html lang="en">
            \\
            \\<head>
            \\  <meta charset="utf-8">
            \\  <meta name="viewport" content="width=device-width, initial-scale=1">
            \\  <title>LoLa Documentation</title>
            \\  <link rel="icon"
            \\    href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAgklEQVR4AWMYWuD7EllJIM4G4g4g5oIJ/odhOJ8wToOxSTXgNxDHoeiBMfA4+wGShjyYOCkG/IGqWQziEzYAoUAeiF9D5U+DxEg14DRU7jWIT5IBIOdCxf+A+CQZAAoopEB7QJwBCBwHiip8UYmRdrAlDpIMgApwQZNnNii5Dq0MBgCxxycBnwEd+wAAAABJRU5ErkJggg==">
            \\  <link rel="stylesheet" href="../documentation.css" />
            \\</head>
            \\
            \\<body class="canvas">
            \\  <div class="flex-main">
            \\    <div class="flex-filler"></div>
            \\    <div class="flex-left sidebar">
            \\      <nav>
            \\        <div class="logo">
            \\          <img src="../img/logo.png" />
            \\        </div>
            \\        <div id="sectPkgs" class="">
            \\          <h2><span>Documents</span></h2>
            \\          <ul id="listPkgs" class="packages">
        );

        for (menu_items, 0..) |menu, i| {
            const is_current = (current_index == i);
            const current_class = if (is_current)
                @as([]const u8, "class=\"active\"")
            else
                "";
            try outfile.writer().print(
                \\<li><a href="{s}" {s}>{s}</a></li>
                \\
            , .{
                std.fs.path.basename(menu.output_file_name),
                current_class,
                menu.header,
            });
        }

        const version_name_str = @as(?[]const u8, version_name) orelse @as([]const u8, "development");
        try outfile.writer().print(
            \\          </ul>
            \\        </div>
            \\        <div id="sectInfo" class="">
            \\          <h2><span>LoLa Version</span></h2>
            \\          <p class="str" id="tdZigVer">{s}</p>
            \\        </div>
            \\      </nav>
            \\    </div>
            \\    <div class="flex-right">
            \\      <div class="wrap">
            \\        <section class="docs">
        , .{
            version_name_str,
        });

        try outfile.writer().writeAll(output);
        try outfile.writeAll(
            \\        </section>
            \\      </div>
            \\      <div class="flex-filler"></div>
            \\    </div>
            \\  </div>
            \\</body>
            \\
            \\</html>
            \\
        );
    }
    return 0;
}

fn markdownToHtmlInternal(resultAllocator: std.mem.Allocator, internalAllocator: std.mem.Allocator, options: koino.Options, markdown: []const u8) ![]u8 {
    var p = try koino.parser.Parser.init(internalAllocator, options);
    try p.feed(markdown);

    var doc = try p.finish();
    p.deinit();

    defer doc.deinit();

    var buffer = std.ArrayList(u8).init(resultAllocator);
    defer buffer.deinit();

    try koino.html.print(buffer.writer(), internalAllocator, p.options, doc);

    return buffer.toOwnedSlice();
}

pub fn markdownToHtml(allocator: std.mem.Allocator, options: koino.Options, markdown: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    return markdownToHtmlInternal(allocator, arena.allocator(), options, markdown);
}
