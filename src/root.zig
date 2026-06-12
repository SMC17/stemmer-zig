//! stemmer — English stemming algorithms in Zig 0.16.
//!
//! Two independent stemmers, pure string operations, no dependencies:
//!
//! - `porter`   — Porter, M.F. (1980) "An algorithm for suffix stripping".
//! - `snowball` — Snowball (Porter2) English stemmer.
//!
//! Both expose the same shape:
//!
//! ```zig
//! var stemmer = @import("stemmer").porter.Stemmer.init(allocator);
//! const stem = try stemmer.stem("relational"); // caller owns
//! defer allocator.free(stem);
//! ```
//!
//! Extracted from a private research repo; algorithms unchanged. Verified by
//! unit tests, committed Brown-vocabulary golden TSVs (tests/golden/), and an
//! inline golden-sample regression test (src/golden_sample_test.zig).

pub const porter = @import("porter.zig");
pub const snowball = @import("snowball.zig");

test {
    _ = porter;
    _ = snowball;
    _ = @import("golden_sample_test.zig");
}
