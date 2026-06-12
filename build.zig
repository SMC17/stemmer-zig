const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const stemmer_mod = b.addModule("stemmer", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .root_module = stemmer_mod,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests (Porter + Snowball + golden sample)");
    test_step.dependOn(&run_tests.step);

    // stemmer-vocab — Brown-vocabulary golden-output generator.
    const vocab_mod = b.createModule(.{
        .root_source_file = b.path("src/vocab_tool.zig"),
        .target = target,
        .optimize = optimize,
    });
    vocab_mod.addImport("stemmer", stemmer_mod);
    const vocab_exe = b.addExecutable(.{
        .name = "stemmer-vocab",
        .root_module = vocab_mod,
    });
    b.installArtifact(vocab_exe);
    const vocab_run = b.addRunArtifact(vocab_exe);
    if (b.args) |args| vocab_run.addArgs(args);
    const vocab_step = b.step("vocab", "Emit word\\tstem TSV for the Brown vocabulary fixture");
    vocab_step.dependOn(&vocab_run.step);
}
