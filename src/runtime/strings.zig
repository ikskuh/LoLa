const std = @import("std");

fn charToInt(c: u8) !u4 {
    return switch (c) {
        '0'...'9' => @intCast(u4, c - '0'),
        'a'...'f' => @intCast(u4, 0xA + c - 'a'),
        'A'...'F' => @intCast(u4, 0xA + c - 'A'),
        else => error.InvalidCharacter,
    };
}

comptime {
    // FIXME: Workaround for linker bug
    if (@import("root") == @import("main.zig")) {
        @export(resolveEscapeSequencesZero, .{
            .linkage = .Strong,
            .name = "resolveEscapeSequencesZero",
        });
        @export(resolveEscapeSequences, .{
            .linkage = .Strong,
            .name = "resolveEscapeSequences",
        });
    }
}

fn resolveEscapeSequencesZero(str: [*:0]u8) callconv(.C) bool {
    var len = std.mem.len(str);

    return resolveEscapeSequences(str, &len);
}

fn resolveEscapeSequences(str: [*]u8, length: *usize) callconv(.C) bool {
    const State = union(enum) {
        default: void,
        escaped: void,
        hexcodeUpper: void,
        hexcodeLower: u4, // contains upper as payload
    };

    var readPtr: usize = 0;
    var writePtr: usize = 0;
    var state: State = .{ .default = {} };

    // Ensure our string is null-terminated after the function
    defer {
        std.debug.assert(writePtr <= length.*);
        str[writePtr] = 0;
        length.* = writePtr;
    }

    while (readPtr < length.*) : (readPtr += 1) {
        const char = str[readPtr];
        std.debug.assert(char != 0);
        const result: ?u8 = switch (state) {
            .default => blk: {
                if (char == '\\') {
                    state = .{ .escaped = {} };
                    break :blk null;
                } else {
                    break :blk char;
                }
            },
            .escaped => blk: {
                if (char == 'x') {
                    state = .{ .hexcodeUpper = {} };
                    break :blk null;
                } else {
                    state = .{ .default = {} };
                    break :blk switch (char) {
                        'a' => 7,
                        'b' => 8,
                        't' => 9,
                        'n' => 10,
                        'r' => 13,
                        'e' => 27,
                        '\"' => 34,
                        '\'' => 39,
                        else => char,
                    };
                }
            },

            .hexcodeUpper => blk: {
                state = .{
                    .hexcodeLower = charToInt(char) catch return false,
                };
                break :blk null;
            },
            .hexcodeLower => |nibble| blk: {
                state = .{ .default = {} };
                const lower = charToInt(char) catch return false;

                break :blk ((@as(u8, nibble) << 4) | @as(u8, lower));
            },
        };
        if (result) |c| {
            str[writePtr] = c;
            writePtr += 1;
        }
    }

    return true;
}

test "resolveEscapeSequences" {
    const TestCase = struct {
        input: [:0]const u8,
        output: []const u8,
    };

    const cases = [_]TestCase{
        .{ .input = "", .output = "" },
        .{ .input = "König", .output = "König" },
        .{ .input = "\\a", .output = "\x07" },
        .{ .input = "\\b", .output = "\x08" },
        .{ .input = "\\t", .output = "\x09" },
        .{ .input = "\\n", .output = "\x0A" },
        .{ .input = "\\r", .output = "\x0D" },
        .{ .input = "\\e", .output = "\x1B" },
        .{ .input = "\\\"", .output = "\x22" },
        .{ .input = "\\\'", .output = "\x27" },
        .{ .input = "\\\\", .output = "\\" },
        .{ .input = "abc\\ndef", .output = "abc\ndef" },
        .{ .input = "\\x01", .output = "\x01" },
        .{ .input = "abc\\x00def", .output = "abc\x00def" },
    };

    var buffer: [256]u8 = undefined;

    for (cases) |case| {
        std.debug.assert(case.input.len < buffer.len);
        for (buffer) |*c|
            c.* = 0xFF;
        std.mem.copy(u8, &buffer, case.input);

        const ptr = @ptrCast([*:0]u8, &buffer);
        var len = case.input.len;

        std.debug.assert(resolveEscapeSequences(ptr, &len) == true);

        std.debug.assert(std.mem.eql(u8, ptr[0..len], case.output));
    }
}
