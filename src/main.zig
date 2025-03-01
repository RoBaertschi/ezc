const std = @import("std");
const ezc = @import("ezc");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const err = gpa.deinit();
        if (err == .leak) {
            @panic("memory leak");
        }
    }
    const allocator = gpa.allocator();
    const file = try std.fs.cwd().openFile("example.ezc", .{
        .mode = .read_only,
    });
    var lexer = try ezc.Lexer.create(file, allocator);
    defer lexer.deinit();
    var parser = try ezc.Parser.create(lexer, allocator);
    var config = try parser.parseConfig();
    defer config.deinit();
    std.debug.print("{!}", .{config});
}

test "simple test" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().openFile("example.ezc", .{
        .mode = .read_only,
    });
    var lexer = try ezc.Lexer.create(file, allocator);
    defer lexer.deinit();
    var parser = try ezc.Parser.create(lexer, allocator);
    var config = try parser.parseConfig();
    defer config.deinit();
    // std.debug.print("{!}", .{config});
}
