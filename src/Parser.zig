//! The Parser for ezc.

const std = @import("std");
const Lexer = @import("Lexer.zig");
const Token = Lexer.Token;
const TokenType = Lexer.TokenType;
const ArrayList = std.ArrayList;
const Alloc = std.mem.Allocator;

const Value = union(enum) {
    boolean: bool,
    integer: i64,
    float: f64,
    array: ArrayList(Value),
    string: []const u8,

    pub fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .boolean => try writer.print("Boolean: {}", .{self.boolean}),
            .integer => try writer.print("Integer: {}", .{self.integer}),
            .float => try writer.print("Float: {}", .{self.float}),
            .array => {
                try writer.print("Array: [", .{});
                for (self.array.items) |item| {
                    try writer.print("{}, ", .{item});
                }
                try writer.print("]", .{});
            },
            .string => try writer.print("String: \"{s}\"", .{self.string}),
        }
    }
};

const Variable = struct {
    name: []const u8,
    value: Value,
    pub fn format(self: Variable, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s} = ({})", .{ self.name, self.value });
    }
};

const Category = struct {
    name: []const u8,
    values: ArrayList(Variable),
    pub fn format(self: Category, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("Category {s} with values: ", .{self.name});
        for (self.values.items) |item| {
            try writer.print("{}, ", .{item});
        }
    }
};

/// All the Memory that Config holds, is owend by Config. Parser will copy the Data from Lexer over to the final Config struct.
const Config = struct {
    categories: ArrayList(Category),
    no_category: ArrayList(Variable),
    allocator: Alloc,
};

const Error = error{
    /// Requires a minus or a variable_name
    expected_statement,
    expected_assign_operator,
    expected_value,
    array_expected_comma_or_rbracket,
    semicolon_expected_after_statement,
    invalid_hex_for_unicode_escape_in_string,
    invalid_escape_code,
    category_requires_valid_variable_name,
    category_requires_minus_after_variable_name,
} || Lexer.Error || error{ Utf8CannotEncodeSurrogateHalf, CodepointTooLarge };

const Self = @This();

cur_token: Token,
peek_token: Token,
lexer: Lexer,
allocator: Alloc,

pub fn create(l: Lexer, alloc: Alloc) Error!Self {
    var lexer = l;
    const cur_token = try lexer.nextToken();
    const peek_token = try lexer.nextToken();

    return Self{
        .cur_token = cur_token,
        .peek_token = peek_token,
        .lexer = lexer,
        .allocator = alloc,
    };
}

fn nextToken(self: *Self) Error!void {
    self.cur_token = self.peek_token;
    self.peek_token = try self.lexer.nextToken();
}

fn expectPeek(self: *Self, tt: TokenType, err: Error) Error!void {
    if (self.peek_token.data != tt) {
        return err;
    }
}
fn expectCur(self: *Self, tt: TokenType, err: Error) Error!void {
    if (self.cur_token.data != tt) {
        return err;
    }
}

fn parseCategoryRoot(self: *Self) Error!ArrayList(Variable) {
    var vars = ArrayList(Variable).init(self.allocator);

    while (true) {
        switch (self.cur_token.data) {
            .variable_name => try vars.append(try self.parseVariableAssign()),
            .minus => return vars,
            .eof => return vars,
            else => return Error.expected_statement,
        }
        try self.expectCur(.semicolon, Error.semicolon_expected_after_statement);
        try self.nextToken();
    }
}

fn parseCategory(self: *Self) Error!Category {
    try self.expectPeek(.variable_name, Error.category_requires_valid_variable_name);
    try self.nextToken();
    const temp_name = self.cur_token.data.variable_name;
    const var_name = try self.allocator.alloc(u8, temp_name.len);
    // Ensure no bugs.
    std.debug.assert(var_name.len >= temp_name.len);
    std.mem.copyForwards(u8, var_name, self.cur_token.data.variable_name);
    try self.expectPeek(.minus, Error.category_requires_minus_after_variable_name);
    try self.nextToken();
    try self.nextToken();
    const values = try self.parseCategoryRoot();

    return Category{ .name = var_name, .values = values };
}

fn parseCategories(self: *Self) Error!ArrayList(Category) {
    var categories = ArrayList(Category).init(self.allocator);
    while (self.cur_token.data != .eof) {
        try categories.append(try self.parseCategory());
    }
    return categories;
}

fn parseVariableAssign(self: *Self) Error!Variable {
    const var_name = try self.allocator.alloc(u8, self.cur_token.data.variable_name.len);
    // Ensure no bugs.
    std.debug.assert(var_name.len >= self.cur_token.data.variable_name.len);
    std.mem.copyForwards(u8, var_name, self.cur_token.data.variable_name);
    try self.expectPeek(.equal, error.expected_assign_operator);
    try self.nextToken();
    try self.nextToken();
    const value = try self.parseValue();
    return .{
        .value = value,
        .name = var_name,
    };
}

fn parseValue(self: *Self) Error!Value {
    const value = switch (self.cur_token.data) {
        .string => blk: {
            var buffer = ArrayList(u8).init(self.allocator);
            var writer = buffer.writer();

            var state: enum { normal, backslash, unicode } = .normal;
            var unicode_buffer = ArrayList(u8).init(self.allocator);
            for (self.cur_token.data.string) |c| {
                switch (state) {
                    .normal => {
                        if (c != '\\') {
                            try writer.writeByte(c);
                        } else {
                            state = .backslash;
                        }
                    },
                    .backslash => {
                        switch (c) {
                            '\\' => try writer.writeByte('\\'),
                            't' => try writer.writeByte('\t'),
                            'n' => try writer.writeByte('\n'),
                            'r' => try writer.writeByte('\r'),
                            '"' => try writer.writeByte('"'),
                            'u' => state = .unicode,
                            else => return Error.invalid_escape_code,
                        }
                        if (state == .backslash) {
                            state = .normal;
                        }
                    },
                    .unicode => {
                        if (unicode_buffer.items.len < 3) {
                            if (Lexer.isHex(c)) {
                                try unicode_buffer.append(c);
                            } else {
                                return Error.invalid_hex_for_unicode_escape_in_string;
                            }
                        } else {
                            if (Lexer.isHex(c)) {
                                try unicode_buffer.append(c);
                            } else {
                                return Error.invalid_hex_for_unicode_escape_in_string;
                            }

                            const unicode: u21 = try std.fmt.parseInt(u21, unicode_buffer.items, 16);
                            var out: [4]u8 = .{ 0, 0, 0, 0 };
                            const unicodes = try std.unicode.utf8Encode(unicode, &out);
                            _ = try writer.write(out[0..unicodes]);
                            state = .normal;
                            unicode_buffer.clearAndFree();
                        }
                    },
                }
            }

            break :blk Value{ .string = try buffer.toOwnedSlice() };
        },
        .true => Value{ .boolean = true },
        .false => Value{ .boolean = false },
        .integer => Value{ .integer = self.cur_token.data.integer },
        .float => Value{ .float = self.cur_token.data.float },
        .lbracket => {
            try self.nextToken();
            var list = ArrayList(Value).init(self.allocator);
            while (true) {
                const value = try self.parseValue();
                try list.append(value);
                if (self.cur_token.data != .comma) {
                    if (self.cur_token.data == .rbracket) {
                        try self.nextToken();
                        break;
                    } else {
                        return Error.array_expected_comma_or_rbracket;
                    }
                }
                try self.nextToken();
            }
            return Value{ .array = list };
        },
        .invalid => {
            std.debug.print("invalid", .{});
            if (self.cur_token.data.invalid) |c| {
                std.debug.print("{c}", .{c});
            }
            std.debug.print("\n", .{});
            return error.expected_value;
        },
        else => return error.expected_value,
    };
    try self.nextToken();
    return value;
}

pub fn parseConfig(self: *Self) Error!Config {
    const root_values = try self.parseCategoryRoot();

    return Config{
        .no_category = root_values,
        .allocator = self.allocator,
        .categories = try self.parseCategories(),
    };
}
