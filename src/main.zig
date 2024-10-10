const std = @import("std");
const ezc = @import("ezc");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const file = try std.fs.cwd().openFile("example.ezc", .{
        .mode = .read_only,
    });
    var lexer = try ezc.Lexer.create(file, allocator);
    var token = try lexer.next_token();
    while (token.data != .eof) {
        std.debug.print("{any}\n", .{token});
        token = try lexer.next_token();
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
