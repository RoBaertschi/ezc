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

const Config = struct {
    categories: ArrayList(Category),
    allocator: Alloc,
};
