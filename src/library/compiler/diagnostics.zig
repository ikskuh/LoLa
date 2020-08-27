const std = @import("std");

pub const MessageKind = enum {
    @"error", warning, notice
};

pub const Message = struct {
    message: []const u8,
    kind: MessageKind,
};

pub const Diagnostics = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator,
    messages: std.ArrayList(Message),

    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .messages = std.ArrayList(Message).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.messages.deinit();
        self.arena.deinit();
    }

    /// Emits a new diagnostic message and appends that to the current output.
    pub fn emit(self: *Self, kind: MessageKind, comptime fmt: []const u8, args: anytype) !void {
        const msg_string = try std.fmt.allocPrint(&self.arena.allocator, fmt, args);
        errdefer self.arena.allocator.free(msg_string);

        try self.messages.append(Message{
            .kind = kind,
            .message = msg_string,
        });
    }

    /// returns true when the collection has any critical messages.
    pub fn hasErrors(self: Self) bool {
        return for (self.messages.items) |msg| {
            if (msg.kind == .@"error")
                break true;
        } else false;
    }
};

test "diagnostic list" {
    var diagnostics = Diagnostics.init(std.testing.allocator);
    defer diagnostics.deinit();

    std.testing.expectEqual(false, diagnostics.hasErrors());
    std.testing.expectEqual(@as(usize, 0), diagnostics.messages.items.len);

    try diagnostics.emit(.warning, "{}", .{"this is a warning!"});

    std.testing.expectEqual(false, diagnostics.hasErrors());
    std.testing.expectEqual(@as(usize, 1), diagnostics.messages.items.len);

    try diagnostics.emit(.notice, "{}", .{"this is a notice!"});

    std.testing.expectEqual(false, diagnostics.hasErrors());
    std.testing.expectEqual(@as(usize, 2), diagnostics.messages.items.len);

    try diagnostics.emit(.@"error", "{}", .{"this is a error!"});

    std.testing.expectEqual(true, diagnostics.hasErrors());
    std.testing.expectEqual(@as(usize, 3), diagnostics.messages.items.len);

    std.testing.expectEqualStrings("this is a warning!", diagnostics.messages.items[0].message);
    std.testing.expectEqualStrings("this is a notice!", diagnostics.messages.items[1].message);
    std.testing.expectEqualStrings("this is a error!", diagnostics.messages.items[2].message);
}
