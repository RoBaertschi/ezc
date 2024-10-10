//! The Parser for ezc.

const std = @import("std");
const ArrayList = std.ArrayList;
const Alloc = std.mem.Allocator;

const Value = union(enum) {
    boolean: bool,
    integer: i64,
    float: f64,
    array: ArrayList(Value),
    string: []const u8,
};

const Category = struct {
    name: []const u8,
    values: ArrayList(Value),
};

/// All the Memory that Config holds, is owend by Config. Parser will copy the Data from Lexer over to the final Config struct.
const Config = struct {
    categories: ArrayList(Category),
    allocator: Alloc,
};

const Self = @This();

pub fn parseConfig() void {}
