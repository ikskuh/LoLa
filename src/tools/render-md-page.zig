const std = @import("std");
const assert = std.debug.assert;

const koino = @import("koino");

const html_prefix =
    \\<!doctype html>
    \\<html lang="en">
    \\
    \\<head>
    \\  <title>LoLa Programming Language</title>
    \\  <link rel="stylesheet" href="style.css">
    \\  <meta charset="UTF-8" />
    \\  <meta name="viewport" content="width=device-width, initial-scale=1">
    \\</head>
    \\
    \\<body>
    \\
;

const html_postfix =
    \\</body>
    \\</html>
    \\
;

pub fn main() !u8 {
    @setEvalBranchQuota(1500);

    var stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = std.process.args();

    const exe_name = try (args.next(&gpa.allocator) orelse return 1);
    gpa.allocator.free(exe_name);

    const input_file_name = try (args.next(&gpa.allocator) orelse return 1);
    defer gpa.allocator.free(input_file_name);

    const output_file_name = try (args.next(&gpa.allocator) orelse return 1);
    defer gpa.allocator.free(output_file_name);

    const options = koino.Options{
        .extensions = .{
            .table = true,
            .autolink = true,
            .strikethrough = true,
        },
    };

    var infile = try std.fs.cwd().openFile(input_file_name, .{});
    defer infile.close();

    var markdown = try infile.reader().readAllAlloc(&gpa.allocator, 1024 * 1024 * 1024);
    defer gpa.allocator.free(markdown);

    var output = try markdownToHtml(&gpa.allocator, options, markdown);
    defer gpa.allocator.free(output);

    var outfile = try std.fs.cwd().createFile(output_file_name, .{});
    defer outfile.close();

    try outfile.writeAll(html_prefix);
    try outfile.writer().writeAll(output);
    try outfile.writeAll(html_postfix);

    return 0;
}

fn markdownToHtmlInternal(resultAllocator: *std.mem.Allocator, internalAllocator: *std.mem.Allocator, options: koino.Options, markdown: []const u8) ![]u8 {
    var p = try koino.parser.Parser.init(internalAllocator, options);
    try p.feed(markdown);

    var doc = try p.finish();
    p.deinit();

    defer doc.deinit();

    return try koino.html.print(resultAllocator, p.options, doc);
}

pub fn markdownToHtml(allocator: *std.mem.Allocator, options: koino.Options, markdown: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    return markdownToHtmlInternal(allocator, &arena.allocator, options, markdown);
}
