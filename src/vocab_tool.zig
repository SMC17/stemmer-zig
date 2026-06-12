//! stemmer-vocab — Brown-vocabulary golden-output generator.
//!
//! Reads a vocabulary fixture (one lowercase word per line; lines starting
//! with '#' are provenance comments and are skipped) and writes
//! `word\tstem` TSV to stdout for the selected stemmer.
//!
//! Usage:
//!   stemmer-vocab <porter|snowball> [vocab_path]
//!
//! Default vocab_path: tests/fixtures/brown_vocab.txt (relative to cwd).
//!
//! The committed golden files under tests/golden/ are produced by running
//! this tool once per algorithm and verified byte-identical across runs.

const std = @import("std");
const stemmer = @import("stemmer");

const Algo = enum { porter, snowball };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var arg_it = try init.minimal.args.iterateAllocator(gpa);
    defer arg_it.deinit();
    _ = arg_it.next(); // executable name

    const algo_arg = arg_it.next() orelse {
        std.debug.print("usage: stemmer-vocab <porter|snowball> [vocab_path]\n", .{});
        return error.MissingAlgorithm;
    };
    const algo: Algo = if (std.mem.eql(u8, algo_arg, "porter"))
        .porter
    else if (std.mem.eql(u8, algo_arg, "snowball"))
        .snowball
    else {
        std.debug.print("unknown algorithm: {s} (expected porter|snowball)\n", .{algo_arg});
        return error.BadAlgorithm;
    };

    const vocab_path = arg_it.next() orelse "tests/fixtures/brown_vocab.txt";

    const contents = try std.Io.Dir.cwd().readFileAlloc(io, vocab_path, gpa, .limited(64 << 20));
    defer gpa.free(contents);

    var porter_stemmer = stemmer.porter.Stemmer.init(gpa);
    var snowball_stemmer = stemmer.snowball.Stemmer.init(gpa);

    var stdout_buf: [16384]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buf);
    const w = &stdout.interface;

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        const result = switch (algo) {
            .porter => try porter_stemmer.stem(line),
            .snowball => try snowball_stemmer.stem(line),
        };
        defer gpa.free(result);

        try w.print("{s}\t{s}\n", .{ line, result });
    }
    try w.flush();
}
