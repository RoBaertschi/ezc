const std = @import("std");
const ArrayList = std.ArrayList;
const Alloc = std.mem.Allocator;

const Loc = struct {
    col: u64,
    row: u64,
    pos: u64,
    pub fn format(self: Loc, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("{}:{}(lex: {})", .{ self.row, self.col, self.pos });
    }
};

const TokenType = enum {
    eof,
    invalid,

    minus,
    semicolon,
    comma,
    equal,
    lbracket,
    rbracket,
    true,
    false,
    integer,
    float,
    string,
    variable_name,
};

const Token = struct {
    /// Inclusive
    start_loc: Loc,
    /// Exclusive
    end_loc: Loc,
    data: union(TokenType) {
        eof: void,
        // The u8 represents the Char, that the lexer expected.
        invalid: ?u8,

        // -
        minus: void,
        // ;
        semicolon: void,
        // ,
        comma: void,
        // =
        equal: void,
        // [
        lbracket: void,
        // ]
        rbracket: void,

        true: void,
        false: void,

        integer: i64,
        float: f64,
        string: []const u8,
        variable_name: []const u8,
    },

    pub fn format(self: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        switch (self.data) {
            .eof => try writer.print("EOF {}:{}", .{ self.start_loc, self.end_loc }),
            .invalid => {
                try writer.print("Invalid Token {}:{}", .{ self.start_loc, self.end_loc });
                if (self.data.invalid) |expected| {
                    try writer.print(" Expected {c}", .{expected});
                }
            },
            .minus => try writer.print("Minus {}:{}", .{ self.start_loc, self.end_loc }),
            .comma => try writer.print("Comma {}:{}", .{ self.start_loc, self.end_loc }),
            .semicolon => try writer.print("Semicolon {}:{}", .{ self.start_loc, self.end_loc }),
            .equal => try writer.print("Equal {}:{}", .{ self.start_loc, self.end_loc }),
            .lbracket => try writer.print("Left Bracket {}:{}", .{ self.start_loc, self.end_loc }),
            .rbracket => try writer.print("Right Bracket {}:{}", .{ self.start_loc, self.end_loc }),
            .true => try writer.print("True Keyword {}:{}", .{ self.start_loc, self.end_loc }),
            .false => try writer.print("False Keyword {}:{}", .{ self.start_loc, self.end_loc }),
            .integer => try writer.print("Integer {}:{} Value: {}", .{ self.start_loc, self.end_loc, self.data.integer }),
            .float => try writer.print("Float {}:{} Value: {}", .{ self.start_loc, self.end_loc, self.data.float }),
            .string => try writer.print("String {}:{} Value: {s}", .{ self.start_loc, self.end_loc, self.data.string }),
            .variable_name => try writer.print("Variable Name {}:{} Value: {s}", .{ self.start_loc, self.end_loc, self.data.variable_name }),
        }
    }
};

inline fn is_digit(ch: u8) bool {
    return '0' <= ch and ch <= '9';
}

inline fn is_hex(ch: u8) bool {
    return is_digit(ch) or ('a' <= ch and ch <= 'f') or ('A' <= ch and ch <= 'F');
}

inline fn is_octal(ch: u8) bool {
    return '0' <= ch and ch <= '7';
}

inline fn is_dot(ch: u8) bool {
    return ch == '.';
}

inline fn is_variable_name(ch: u8) bool {
    return ('a' <= ch and ch <= 'z') or ('A' <= ch and ch <= 'Z') or ch == '_' or is_digit(ch);
}

inline fn is_first_variable_name_char(ch: u8) bool {
    return ('a' <= ch and ch <= 'z') or ('A' <= ch and ch <= 'Z') or ch == '_';
}

inline fn is_whitespace(ch: u8) bool {
    return ch == '\n' or ch == '\t' or ch == '\r' or ch == ' ';
}

pub const Error = error{
    invalid_hex_literal,
    invalid_octal_literal,
} || Alloc.Error || std.fmt.ParseFloatError || std.fmt.ParseIntError;

cur_loc: Loc,
cur_pos: u64,
peek_pos: u64,
ch: u8,
string: []u8,
allocator: Alloc,
potential_error: ?struct {
    error_pos: Loc,
},

const Self = @This();

pub fn create(file: std.fs.File, allocator: Alloc) (Alloc.Error || std.fs.File.Reader.Error || error{FileTooBig})!Self {
    const string = try file.readToEndAlloc(allocator, std.math.maxInt(u64));

    const self = Self{
        .string = string,
        .allocator = allocator,
        .cur_pos = 0,
        .peek_pos = 1,
        .ch = string[0],
        .potential_error = null,
        .cur_loc = .{
            .col = 1,
            .row = 1,
            .pos = 0,
        },
    };
    return self;
}

fn read_char(self: *Self) void {
    if (self.peek_pos >= self.string.len) {
        self.ch = 0;
    } else {
        self.ch = self.string[self.peek_pos];
        self.cur_loc.col += 1;
        if (self.ch == '\n') {
            self.cur_loc.col = 0;
            self.cur_loc.row += 1;
        }
    }
    self.cur_pos = self.peek_pos;
    self.cur_loc.pos = self.cur_pos;
    self.peek_pos += 1;
}

fn read_number(self: *Self) Error!Token {
    const start_loc = self.cur_loc;
    const start_pos = self.cur_pos;
    var dot_type: enum { normal, begin, end } = .normal;

    if (self.ch == '.') {
        dot_type = .begin;
    }
    while (is_digit(self.ch)) self.read_char();

    if (self.ch == '.') {
        self.read_char();
        if (!is_digit(self.ch)) {
            dot_type = .end;
        }
        while (is_digit(self.ch)) self.read_char();

        const value = switch (dot_type) {
            .normal => try std.fmt.parseFloat(f64, self.string[start_pos..self.cur_pos]),
            .begin => blk: {
                const fullFloat = try std.mem.concat(self.allocator, u8, &[_][]const u8{ @as([]const u8, "0"), self.string[start_pos..self.cur_pos] });
                defer self.allocator.free(fullFloat);
                break :blk try std.fmt.parseFloat(f64, fullFloat);
            },
            .end => blk: {
                const fullFloat = try std.mem.concat(self.allocator, u8, &[_][]const u8{ self.string[start_pos..self.cur_pos], @as([]const u8, "0") });
                defer self.allocator.free(fullFloat);
                break :blk try std.fmt.parseFloat(f64, fullFloat);
            },
        };

        return Token{ .data = .{ .float = value }, .start_loc = start_loc, .end_loc = self.cur_loc };
    }

    const value = try std.fmt.parseInt(i64, self.string[start_pos..self.cur_pos], 10);
    return Token{ .data = .{ .integer = value }, .start_loc = start_loc, .end_loc = self.cur_loc };
}

pub fn read_octal(self: *Self) Error!Token {
    const start_loc = self.cur_loc;
    const start_pos = self.cur_pos;
    self.read_char();
    self.read_char();

    if (!is_octal(self.ch)) {
        return Token{ .data = .{ .invalid = self.ch }, .start_loc = start_loc, .end_loc = self.cur_loc };
    }
    while (is_octal(self.ch)) self.read_char();
    const value = try std.fmt.parseInt(i64, self.string[start_pos..self.cur_pos], 0);
    return Token{ .data = .{ .integer = value }, .start_loc = start_loc, .end_loc = self.cur_loc };
}

pub fn read_hex(self: *Self) Error!Token {
    const start_loc = self.cur_loc;
    const start_pos = self.cur_pos;
    // currently: 0xFFF
    //            ^
    self.read_char();
    // currently: 0xFFF
    //             ^
    self.read_char();
    // currently: 0xFFF
    //              ^

    if (!is_hex(self.ch)) {
        return Token{ .data = .{ .invalid = self.ch }, .start_loc = start_loc, .end_loc = self.cur_loc };
    }
    while (is_hex(self.ch)) self.read_char();
    const value = try std.fmt.parseInt(i64, self.string[start_pos..self.cur_pos], 0);
    return Token{ .data = .{ .integer = value }, .start_loc = start_loc, .end_loc = self.cur_loc };
}

fn read_variable_name(self: *Self) Error!Token {
    const start_loc = self.cur_loc;
    const start_pos = self.cur_pos;

    self.read_char();
    while (is_variable_name(self.ch)) self.read_char();

    if (std.mem.eql(u8, self.string[start_pos..self.cur_pos], "true")) {
        return Token{ .data = .true, .start_loc = start_loc, .end_loc = self.cur_loc };
    } else if (std.mem.eql(u8, self.string[start_pos..self.cur_pos], "false")) {
        return Token{ .data = .false, .start_loc = start_loc, .end_loc = self.cur_loc };
    }

    return Token{ .data = .{ .variable_name = self.string[start_pos..self.cur_pos] }, .start_loc = start_loc, .end_loc = self.cur_loc };
}

fn peek_char(self: *Self) u8 {
    if (self.peek_pos >= self.string.len) {
        return 0;
    }
    return self.string[self.peek_pos];
}

fn skip_whitespace(self: *Self) void {
    while (is_whitespace(self.ch)) self.read_char();
}

/// The lexer does not take care of escaped tokens in a string except for \", as that is required to be correctly handled
fn read_string(self: *Self) Error!Token {
    const start_loc = self.cur_loc;
    const start_pos = self.cur_pos;

    if (self.ch == '"') {
        self.read_char();
    }
    while (self.ch != '"') {
        switch (self.ch) {
            '\\' => {
                if (self.peek_char() == '"') {
                    self.read_char();
                    self.read_char();
                } else {
                    self.read_char();
                }
            },
            else => self.read_char(),
        }
    }
    const string = self.string[(start_pos + 1)..self.cur_pos];
    self.read_char();

    return Token{ .data = .{ .string = string }, .start_loc = start_loc, .end_loc = self.cur_loc };
}

pub fn next_token(self: *Self) Error!Token {
    self.skip_whitespace();
    const empty_loc = Loc{ .col = 0, .row = 0, .pos = 0 };
    var new_token = switch (self.ch) {
        0 => return Token{ .data = .eof, .start_loc = self.cur_loc, .end_loc = self.cur_loc },
        '-' => Token{ .data = .minus, .start_loc = self.cur_loc, .end_loc = empty_loc },
        ';' => Token{ .data = .semicolon, .start_loc = self.cur_loc, .end_loc = empty_loc },
        ',' => Token{ .data = .comma, .start_loc = self.cur_loc, .end_loc = empty_loc },
        '=' => Token{ .data = .equal, .start_loc = self.cur_loc, .end_loc = empty_loc },
        '[' => Token{ .data = .lbracket, .start_loc = self.cur_loc, .end_loc = empty_loc },
        ']' => Token{ .data = .rbracket, .start_loc = self.cur_loc, .end_loc = empty_loc },
        '0' => {
            if (self.peek_char() == 'o') {
                return try self.read_octal();
            } else if (self.peek_char() == 'x') {
                return try self.read_hex();
            } else {
                return try self.read_number();
            }
        },

        else => blk: {
            if (is_dot(self.ch) or is_digit(self.ch)) {
                return self.read_number();
            } else if (is_first_variable_name_char(self.ch)) {
                return self.read_variable_name();
            } else if (self.ch == '"') {
                return self.read_string();
            }
            break :blk Token{ .data = .{ .invalid = null }, .start_loc = self.cur_loc, .end_loc = empty_loc };
        },
    };

    self.read_char();

    new_token.end_loc = self.cur_loc;

    return new_token;
}

/// This will invalidate all tokens. Remember that.
pub fn destroy(self: *Self) void {
    self.allocator.free(self.string);
}
