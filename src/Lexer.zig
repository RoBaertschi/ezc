const std = @import("std");
const ArrayList = std.ArrayList;
const Alloc = std.mem.Allocator;

pub const Loc = struct {
    col: u64,
    row: u64,
    pos: u64,
    pub fn format(self: Loc, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("{}:{}(lex: {})", .{ self.row, self.col, self.pos });
    }
};

pub const TokenType = enum {
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

pub const Token = struct {
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

inline fn isDigit(ch: u8) bool {
    return '0' <= ch and ch <= '9';
}

pub inline fn isHex(ch: u8) bool {
    return isDigit(ch) or ('a' <= ch and ch <= 'f') or ('A' <= ch and ch <= 'F');
}

inline fn isOctal(ch: u8) bool {
    return '0' <= ch and ch <= '7';
}

inline fn isDot(ch: u8) bool {
    return ch == '.';
}

inline fn isVariableName(ch: u8) bool {
    return ('a' <= ch and ch <= 'z') or ('A' <= ch and ch <= 'Z') or ch == '_' or isDigit(ch);
}

inline fn isFirstVariableNameChar(ch: u8) bool {
    return ('a' <= ch and ch <= 'z') or ('A' <= ch and ch <= 'Z') or ch == '_';
}

inline fn isWhitespace(ch: u8) bool {
    return ch == '\n' or ch == '\t' or ch == '\r' or ch == ' ';
}

pub const Error = error{
    InvalidHexLiteral,
    InvalidOctalLiteral,
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

fn readChar(self: *Self) void {
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

fn readNumber(self: *Self) Error!Token {
    var sign: enum { plus, minus } = .plus;
    if (self.ch == '-') {
        sign = .minus;
        self.readChar();
    }
    const start_loc = self.cur_loc;
    const start_pos = self.cur_pos;
    var dot_type: enum { normal, begin, end } = .normal;

    if (self.ch == '.') {
        dot_type = .begin;
    }
    while (isDigit(self.ch)) self.readChar();

    if (self.ch == '.') {
        self.readChar();
        if (!isDigit(self.ch)) {
            dot_type = .end;
        }
        while (isDigit(self.ch)) self.readChar();

        var value = switch (dot_type) {
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

        if (sign == .minus) {
            value = -value;
        }

        return Token{ .data = .{ .float = value }, .start_loc = start_loc, .end_loc = self.cur_loc };
    }

    var value = try std.fmt.parseInt(i64, self.string[start_pos..self.cur_pos], 10);
    if (sign == .minus) {
        value = -value;
    }
    return Token{ .data = .{ .integer = value }, .start_loc = start_loc, .end_loc = self.cur_loc };
}

pub fn readOctal(self: *Self) Error!Token {
    const start_loc = self.cur_loc;
    const start_pos = self.cur_pos;
    self.readChar();
    self.readChar();

    if (!isOctal(self.ch)) {
        return Token{ .data = .{ .invalid = self.ch }, .start_loc = start_loc, .end_loc = self.cur_loc };
    }
    while (isOctal(self.ch)) self.readChar();
    const value = try std.fmt.parseInt(i64, self.string[start_pos..self.cur_pos], 0);
    return Token{ .data = .{ .integer = value }, .start_loc = start_loc, .end_loc = self.cur_loc };
}

pub fn readHex(self: *Self) Error!Token {
    const start_loc = self.cur_loc;
    const start_pos = self.cur_pos;
    // currently: 0xFFF
    //            ^
    self.readChar();
    // currently: 0xFFF
    //             ^
    self.readChar();
    // currently: 0xFFF
    //              ^

    if (!isHex(self.ch)) {
        return Token{ .data = .{ .invalid = self.ch }, .start_loc = start_loc, .end_loc = self.cur_loc };
    }
    while (isHex(self.ch)) self.readChar();
    const value = try std.fmt.parseInt(i64, self.string[start_pos..self.cur_pos], 0);
    return Token{ .data = .{ .integer = value }, .start_loc = start_loc, .end_loc = self.cur_loc };
}

fn readVariableName(self: *Self) Error!Token {
    const start_loc = self.cur_loc;
    const start_pos = self.cur_pos;

    self.readChar();
    while (isVariableName(self.ch)) self.readChar();

    if (std.mem.eql(u8, self.string[start_pos..self.cur_pos], "true")) {
        return Token{ .data = .true, .start_loc = start_loc, .end_loc = self.cur_loc };
    } else if (std.mem.eql(u8, self.string[start_pos..self.cur_pos], "false")) {
        return Token{ .data = .false, .start_loc = start_loc, .end_loc = self.cur_loc };
    }

    return Token{ .data = .{ .variable_name = self.string[start_pos..self.cur_pos] }, .start_loc = start_loc, .end_loc = self.cur_loc };
}

fn peekChar(self: *Self) u8 {
    if (self.peek_pos >= self.string.len) {
        return 0;
    }
    return self.string[self.peek_pos];
}

fn skipWhitespace(self: *Self) void {
    while (isWhitespace(self.ch)) self.readChar();
}

/// The lexer does not take care of escaped tokens in a string except for \", as that is required to be correctly handled
fn readString(self: *Self) Error!Token {
    const start_loc = self.cur_loc;
    const start_pos = self.cur_pos;

    if (self.ch == '"') {
        self.readChar();
    }
    while (self.ch != '"') {
        switch (self.ch) {
            '\\' => {
                if (self.peekChar() == '"') {
                    self.readChar();
                    self.readChar();
                } else {
                    self.readChar();
                }
            },
            else => self.readChar(),
        }
    }
    const string = self.string[(start_pos + 1)..self.cur_pos];
    self.readChar();

    return Token{ .data = .{ .string = string }, .start_loc = start_loc, .end_loc = self.cur_loc };
}

pub fn nextToken(self: *Self) Error!Token {
    self.skipWhitespace();
    const empty_loc = Loc{ .col = 0, .row = 0, .pos = 0 };
    var new_token = switch (self.ch) {
        0 => return Token{ .data = .eof, .start_loc = self.cur_loc, .end_loc = self.cur_loc },
        '-' => blk: {
            if (isDigit(self.peekChar()) or isDot(self.peekChar())) {
                return self.readNumber();
            }
            break :blk Token{ .data = .minus, .start_loc = self.cur_loc, .end_loc = empty_loc };
        },
        ';' => Token{ .data = .semicolon, .start_loc = self.cur_loc, .end_loc = empty_loc },
        ',' => Token{ .data = .comma, .start_loc = self.cur_loc, .end_loc = empty_loc },
        '=' => Token{ .data = .equal, .start_loc = self.cur_loc, .end_loc = empty_loc },
        '[' => Token{ .data = .lbracket, .start_loc = self.cur_loc, .end_loc = empty_loc },
        ']' => Token{ .data = .rbracket, .start_loc = self.cur_loc, .end_loc = empty_loc },
        '0' => {
            if (self.peekChar() == 'o') {
                return try self.readOctal();
            } else if (self.peekChar() == 'x') {
                return try self.readHex();
            } else {
                return try self.readNumber();
            }
        },

        else => blk: {
            if (isDot(self.ch) or isDigit(self.ch)) {
                return self.readNumber();
            } else if (isFirstVariableNameChar(self.ch)) {
                return self.readVariableName();
            } else if (self.ch == '"') {
                return self.readString();
            }
            break :blk Token{ .data = .{ .invalid = null }, .start_loc = self.cur_loc, .end_loc = empty_loc };
        },
    };

    self.readChar();

    new_token.end_loc = self.cur_loc;

    return new_token;
}

/// This will invalidate all tokens. Remember that.
pub fn destroy(self: *Self) void {
    self.allocator.free(self.string);
}
