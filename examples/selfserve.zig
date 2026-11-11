//! Synthetic lexical task: apply both stemmers to two small input words.
const std = @import("std");
const lib = @import("lib");
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var porter = lib.porter.Stemmer.init(allocator);
    var snowball = lib.snowball.Stemmer.init(allocator);
    const words = [_][]const u8{ "running", "cats" };
    const expected = [_][]const u8{ "run", "cat" };
    for (words, expected) |word, want| {
        const first = try porter.stem(word);
        defer allocator.free(first);
        const second = try snowball.stem(word);
        defer allocator.free(second);
        if (!std.mem.eql(u8, first, want) or !std.mem.eql(u8, second, want)) return error.StemMismatch;
        std.debug.print("fixture: {s} -> {s} (porter and snowball)\n", .{ word, want });
    }
}
