const std = @import("std");

pub const Type = enum {
    void,
    number,
    string,
    boolean,
    array,
    object,

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.writerAll(@tagName(value));
    }
};

pub const TypeSet = struct {
    const Self = @This();

    pub const empty = Self{
        .void = false,
        .number = false,
        .string = false,
        .boolean = false,
        .array = false,
        .object = false,
    };

    pub const any = Self{
        .void = true,
        .number = true,
        .string = true,
        .boolean = true,
        .array = true,
        .object = true,
    };

    void: bool,
    number: bool,
    string: bool,
    boolean: bool,
    array: bool,
    object: bool,

    pub fn from(value_type: Type) Self {
        return Self{
            .void = (value_type == .void),
            .number = (value_type == .number),
            .string = (value_type == .string),
            .boolean = (value_type == .boolean),
            .array = (value_type == .array),
            .object = (value_type == .object),
        };
    }

    pub fn init(list: anytype) Self {
        var set = TypeSet.empty;
        inline for (list) |item| {
            set = set.@"union"(from(item));
        }
        return set;
    }

    pub fn contains(self: Self, item: Type) bool {
        return switch (item) {
            .void => self.void,
            .number => self.number,
            .string => self.string,
            .boolean => self.boolean,
            .array => self.array,
            .object => self.object,
        };
    }

    /// Returns a type set that only contains all types that are contained in both parameters.
    pub fn intersection(a: Self, b: Self) Self {
        var result: Self = undefined;
        inline for (std.meta.fields(Self)) |fld| {
            @field(result, fld.name) = @field(a, fld.name) and @field(b, fld.name);
        }
        return result;
    }

    /// Returns a type set that contains all types that are contained in any of the parameters.
    pub fn @"union"(a: Self, b: Self) Self {
        var result: Self = undefined;
        inline for (std.meta.fields(Self)) |fld| {
            @field(result, fld.name) = @field(a, fld.name) or @field(b, fld.name);
        }
        return result;
    }

    pub fn isEmpty(self: Self) bool {
        inline for (std.meta.fields(Self)) |fld| {
            if (@field(self, fld.name))
                return false;
        }
        return true;
    }

    pub fn isAny(self: Self) bool {
        inline for (std.meta.fields(Self)) |fld| {
            if (!@field(self, fld.name))
                return false;
        }
        return true;
    }

    /// Tests if the type set contains at least one common type.
    pub fn areCompatible(a: Self, b: Self) bool {
        return !intersection(a, b).isEmpty();
    }

    pub fn format(value: Self, writer: *std.Io.Writer) !void {
        if (value.isEmpty()) {
            try writer.writeAll("none");
        } else if (value.isAny()) {
            try writer.writeAll("any");
        } else {
            var separate = false;
            inline for (std.meta.fields(Self)) |fld| {
                if (@field(value, fld.name)) {
                    if (separate) {
                        try writer.writeAll("|");
                    }
                    separate = true;
                    try writer.writeAll(fld.name);
                }
            }
        }
    }
};
