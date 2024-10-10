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

const Error = error{};

const Self = @This();

cur_token: Token,
peek_token: Token,
lexer: Lexer,

pub fn init(lexer: Lexer) Self {
    const cur_token = lexer.nextToken();
    const peek_token = lexer.nextToken();

    return Self{
        .cur_token = cur_token,
        .peek_token = peek_token,
        .lexer = lexer,
    };
}

pub fn parseConfig(self: *Self) Error!Config {
    _ = self;
}
