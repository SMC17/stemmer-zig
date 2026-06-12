//! Snowball (Porter2) English Stemmer
//! Based on: https://snowballstem.org/algorithms/english/stemmer.html
//!
//! An improved version of the Porter stemmer with:
//! - Better apostrophe handling
//! - R1/R2 region detection (instead of measure)
//! - More comprehensive suffix rules
//! - Better morphophonological transformations
//!
//! Extracted from a private research repo (algorithm and expected test
//! values unchanged); migrated to Zig 0.16. The only port-time change is
//! memory management: `stem` now runs all intermediate steps inside an
//! internal arena and returns a single caller-owned allocation, matching
//! the Porter module's contract. (The original allocated intermediates on
//! the caller's allocator and relied on the caller using an arena.)

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const Stemmer = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Stemmer {
        return .{ .allocator = allocator };
    }

    /// Main stemming function - applies all steps in sequence.
    /// Returns a newly allocated string; caller owns the returned memory.
    pub fn stem(self: *Stemmer, word: []const u8) ![]const u8 {
        if (word.len < 3) {
            return try self.allocator.dupe(u8, word);
        }

        // All intermediate allocations go into an arena freed at end;
        // only the final result is duplicated onto the caller's allocator.
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var temp_stemmer = Stemmer.init(arena.allocator());

        const result = try temp_stemmer.stemSteps(word);
        return try self.allocator.dupe(u8, result);
    }

    /// The original step sequence, unchanged. Allocates on self.allocator.
    fn stemSteps(self: *Stemmer, word: []const u8) ![]const u8 {
        const working_buf = try self.allocator.dupe(u8, word);

        // Convert to lowercase
        for (working_buf) |*c| {
            c.* = std.ascii.toLower(c.*);
        }

        // Step 0: Remove apostrophes
        var result = try self.step0(working_buf);

        // Step 1a: Handle plurals and past participles
        result = try self.step1a(result);
        if (result.len < 2) return result;

        // Special word check after step 1a
        if (isSpecialWord(result)) {
            return result;
        }

        // Step 1b: Handle -ed/-ing
        result = try self.step1b(result);
        if (result.len < 2) return result;

        // Step 1c: Replace suffix y or Y with i
        result = try self.step1c(result);
        if (result.len < 2) return result;

        // Step 2: Map double suffixes to single ones
        result = try self.step2(result);
        if (result.len < 2) return result;

        // Step 3: Handle various suffixes
        result = try self.step3(result);
        if (result.len < 2) return result;

        // Step 4: Remove various endings
        result = try self.step4(result);
        if (result.len < 2) return result;

        // Step 5: Final cleanup (but not if word is too short)
        if (result.len >= 3) {
            result = try self.step5(result);
        }

        return result;
    }

    // Step 0: Remove 's, 's', s'
    fn step0(self: *Stemmer, word: []const u8) ![]const u8 {
        // Remove 's' (3 chars)
        if (endsWith(word, "'s'")) {
            return try self.allocator.dupe(u8, word[0 .. word.len - 3]);
        }
        // Remove 's (2 chars)
        if (endsWith(word, "'s")) {
            return try self.allocator.dupe(u8, word[0 .. word.len - 2]);
        }
        // Remove ' (1 char)
        if (endsWith(word, "'")) {
            return try self.allocator.dupe(u8, word[0 .. word.len - 1]);
        }
        return try self.allocator.dupe(u8, word);
    }

    // Step 1a: Handle sses, ied/ies, us/ss, s
    fn step1a(self: *Stemmer, word: []const u8) ![]const u8 {
        // sses → ss
        if (endsWith(word, "sses")) {
            return try self.allocator.dupe(u8, word[0 .. word.len - 2]);
        }

        // ied/ies → i or ie (based on word length, not base length)
        if (endsWith(word, "ied") or endsWith(word, "ies")) {
            const base_len = word.len - 3;
            if (word.len > 4) {
                return try concat(self.allocator, word[0..base_len], "i");
            } else {
                return try concat(self.allocator, word[0..base_len], "ie");
            }
        }

        // us/ss unchanged
        if (endsWith(word, "us") or endsWith(word, "ss")) {
            return try self.allocator.dupe(u8, word);
        }

        // s → (delete if preceded by vowel in stem)
        if (endsWith(word, "s") and word.len > 2) {
            const stem_part = word[0 .. word.len - 1];
            // Check if there's a vowel before the 's'
            if (containsVowel(stem_part)) {
                return try self.allocator.dupe(u8, stem_part);
            }
        }

        return try self.allocator.dupe(u8, word);
    }

    // Step 1b: Handle -ed/-edly/-ing/-ingly
    fn step1b(self: *Stemmer, word: []const u8) ![]const u8 {
        // Try longest suffixes first
        const suffixes = [_][]const u8{ "eedly", "ingly", "edly", "ing", "ed" };

        for (suffixes) |suffix| {
            if (endsWith(word, suffix)) {
                if (std.mem.eql(u8, suffix, "eedly")) {
                    // eedly → ee (if in R1)
                    const r1_pos = getR1(word);
                    const stem_len = word.len - suffix.len;
                    if (stem_len >= r1_pos) {
                        return try concat(self.allocator, word[0..stem_len], "ee");
                    }
                } else {
                    // ed/edly/ing/ingly → (delete if preceded by vowel in stem)
                    const stem_part = word[0 .. word.len - suffix.len];
                    if (containsVowel(stem_part)) {
                        // Post-processing on the stem

                        // at/bl/iz → add e
                        if (endsWith(stem_part, "at") or endsWith(stem_part, "bl") or endsWith(stem_part, "iz")) {
                            return try concat(self.allocator, stem_part, "e");
                        }

                        // Double consonant → remove one (except ll, ss, zz)
                        if (stem_part.len >= 2) {
                            const last = stem_part[stem_part.len - 1];
                            const prev = stem_part[stem_part.len - 2];
                            if (last == prev and !isVowelChar(last)) {
                                if (last != 'l' and last != 's' and last != 'z') {
                                    return try self.allocator.dupe(u8, stem_part[0 .. stem_part.len - 1]);
                                }
                            }
                        }

                        // Short word → add e
                        if (isShortWord(stem_part)) {
                            return try concat(self.allocator, stem_part, "e");
                        }

                        return try self.allocator.dupe(u8, stem_part);
                    }
                }
            }
        }

        return try self.allocator.dupe(u8, word);
    }

    // Step 1c: Replace suffix y or Y with i if preceded by consonant (and not at start)
    fn step1c(self: *Stemmer, word: []const u8) ![]const u8 {
        if (word.len > 2) {
            const last = word[word.len - 1];
            if ((last == 'y' or last == 'Y') and !isVowelChar(word[word.len - 2])) {
                const result = try self.allocator.dupe(u8, word);
                result[result.len - 1] = 'i';
                return result;
            }
        }
        return try self.allocator.dupe(u8, word);
    }

    // Step 2: Map double suffixes to single ones
    fn step2(self: *Stemmer, word: []const u8) ![]const u8 {
        const r1_pos = getR1(word);

        const replacements = [_]struct { suffix: []const u8, replacement: []const u8 }{
            .{ .suffix = "ational", .replacement = "ate" },
            .{ .suffix = "tional", .replacement = "tion" },
            .{ .suffix = "enci", .replacement = "ence" },
            .{ .suffix = "anci", .replacement = "ance" },
            .{ .suffix = "abli", .replacement = "able" },
            .{ .suffix = "entli", .replacement = "ent" },
            .{ .suffix = "izer", .replacement = "ize" },
            .{ .suffix = "ization", .replacement = "ize" },
            .{ .suffix = "ation", .replacement = "ate" },
            .{ .suffix = "ator", .replacement = "ate" },
            .{ .suffix = "alism", .replacement = "al" },
            .{ .suffix = "aliti", .replacement = "al" },
            .{ .suffix = "alli", .replacement = "al" },
            .{ .suffix = "fulness", .replacement = "ful" },
            .{ .suffix = "ousli", .replacement = "ous" },
            .{ .suffix = "ousness", .replacement = "ous" },
            .{ .suffix = "iveness", .replacement = "ive" },
            .{ .suffix = "iviti", .replacement = "ive" },
            .{ .suffix = "biliti", .replacement = "ble" },
            .{ .suffix = "bli", .replacement = "ble" },
            .{ .suffix = "fulli", .replacement = "ful" },
            .{ .suffix = "lessli", .replacement = "less" },
            .{ .suffix = "ogi", .replacement = "og" }, // if preceded by l
            .{ .suffix = "li", .replacement = "" }, // if preceded by valid li ending
        };

        for (replacements) |pair| {
            if (endsWith(word, pair.suffix)) {
                const stem_len = word.len - pair.suffix.len;

                // Check if suffix is in R1
                if (stem_len < r1_pos) continue;

                // Special cases
                if (std.mem.eql(u8, pair.suffix, "ogi")) {
                    if (stem_len > 0 and word[stem_len - 1] == 'l') {
                        return try concat(self.allocator, word[0..stem_len], pair.replacement);
                    }
                    continue;
                }

                if (std.mem.eql(u8, pair.suffix, "li")) {
                    if (stem_len > 0 and isValidLiEnding(word[stem_len - 1])) {
                        return try self.allocator.dupe(u8, word[0..stem_len]);
                    }
                    continue;
                }

                return try concat(self.allocator, word[0..stem_len], pair.replacement);
            }
        }

        return try self.allocator.dupe(u8, word);
    }

    // Step 3: Handle more suffixes
    fn step3(self: *Stemmer, word: []const u8) ![]const u8 {
        const r1_pos = getR1(word);
        const r2_pos = getR2(word);

        const replacements = [_]struct { suffix: []const u8, replacement: []const u8, use_r2: bool }{
            .{ .suffix = "ational", .replacement = "ate", .use_r2 = false },
            .{ .suffix = "tional", .replacement = "tion", .use_r2 = false },
            .{ .suffix = "alize", .replacement = "al", .use_r2 = false },
            .{ .suffix = "icate", .replacement = "ic", .use_r2 = false },
            .{ .suffix = "iciti", .replacement = "ic", .use_r2 = false },
            .{ .suffix = "ical", .replacement = "ic", .use_r2 = false },
            .{ .suffix = "ful", .replacement = "", .use_r2 = false },
            .{ .suffix = "ness", .replacement = "", .use_r2 = false },
            .{ .suffix = "ative", .replacement = "", .use_r2 = true },
        };

        for (replacements) |pair| {
            if (endsWith(word, pair.suffix)) {
                const stem_len = word.len - pair.suffix.len;
                const required_pos = if (pair.use_r2) r2_pos else r1_pos;

                if (stem_len >= required_pos) {
                    return try concat(self.allocator, word[0..stem_len], pair.replacement);
                }
            }
        }

        return try self.allocator.dupe(u8, word);
    }

    // Step 4: Remove various suffixes in R2
    fn step4(self: *Stemmer, word: []const u8) ![]const u8 {
        const r2_pos = getR2(word);

        const suffixes = [_][]const u8{
            "al",  "ance", "ence",  "er",   "ic",  "able", "ible",
            "ant", "ement", "ment", "ent",  "ism", "ate",  "iti",
            "ous", "ive",  "ize",
        };

        for (suffixes) |suffix| {
            if (endsWith(word, suffix)) {
                const stem_len = word.len - suffix.len;

                // Special handling for -ion
                if (std.mem.eql(u8, suffix, "ion")) {
                    if (stem_len > 0 and stem_len >= r2_pos) {
                        const prev = word[stem_len - 1];
                        if (prev == 's' or prev == 't') {
                            return try self.allocator.dupe(u8, word[0..stem_len]);
                        }
                    }
                    continue;
                }

                if (stem_len >= r2_pos) {
                    return try self.allocator.dupe(u8, word[0..stem_len]);
                }
            }
        }

        // Also check for -ion specifically
        if (endsWith(word, "ion")) {
            const stem_len = word.len - 3;
            if (stem_len > 0 and stem_len >= r2_pos) {
                const prev = word[stem_len - 1];
                if (prev == 's' or prev == 't') {
                    return try self.allocator.dupe(u8, word[0..stem_len]);
                }
            }
        }

        return try self.allocator.dupe(u8, word);
    }

    // Step 5: Final cleanup - remove/handle trailing e and l
    fn step5(self: *Stemmer, word: []const u8) ![]const u8 {
        const r1_pos = getR1(word);
        const r2_pos = getR2(word);

        // Step 5a: Handle trailing 'e'
        if (endsWith(word, "e")) {
            const stem_part = word[0 .. word.len - 1];

            // Delete if in R2
            if (word.len - 1 >= r2_pos) {
                return try self.allocator.dupe(u8, stem_part);
            }

            // Or if in R1 and not preceded by short syllable
            if (word.len - 1 >= r1_pos and !endsInShortSyllable(stem_part)) {
                return try self.allocator.dupe(u8, stem_part);
            }
        }

        // Step 5b: Handle trailing 'l'
        if (endsWith(word, "l") and word.len > 1) {
            if (word.len - 1 >= r2_pos and word[word.len - 2] == 'l') {
                return try self.allocator.dupe(u8, word[0 .. word.len - 1]);
            }
        }

        return try self.allocator.dupe(u8, word);
    }
};

// Helper functions

fn isVowelChar(c: u8) bool {
    return c == 'a' or c == 'e' or c == 'i' or c == 'o' or c == 'u' or c == 'y';
}

fn containsVowel(word: []const u8) bool {
    for (word) |c| {
        if (isVowelChar(c)) return true;
    }
    return false;
}

fn endsWith(word: []const u8, suffix: []const u8) bool {
    if (word.len < suffix.len) return false;
    return std.mem.eql(u8, word[word.len - suffix.len ..], suffix);
}

fn concat(allocator: Allocator, a: []const u8, b: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, a.len + b.len);
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}

/// Get position of R1 region (region after first non-vowel following a vowel)
/// Special handling for: gener-, commun-, arsen-
fn getR1(word: []const u8) usize {
    // Special cases
    if (std.mem.startsWith(u8, word, "gener")) return 5;
    if (std.mem.startsWith(u8, word, "commun")) return 6;
    if (std.mem.startsWith(u8, word, "arsen")) return 5;

    // General case: find first vowel, then first non-vowel after it
    var found_vowel = false;
    for (word, 0..) |c, i| {
        if (isVowelChar(c)) {
            found_vowel = true;
        } else if (found_vowel) {
            return i + 1;
        }
    }
    return word.len;
}

/// Get position of R2 region (region after first non-vowel following a vowel in R1)
fn getR2(word: []const u8) usize {
    const r1_pos = getR1(word);
    if (r1_pos >= word.len) return word.len;

    const r1_region = word[r1_pos..];
    var found_vowel = false;
    for (r1_region, 0..) |c, i| {
        if (isVowelChar(c)) {
            found_vowel = true;
        } else if (found_vowel) {
            return r1_pos + i + 1;
        }
    }
    return word.len;
}

/// Check if word ends in a short syllable
/// A short syllable: (consonant) vowel non-vowel-other-than-w-x-Y
fn endsInShortSyllable(word: []const u8) bool {
    if (word.len < 2) return false;

    const last = word[word.len - 1];
    const prev = word[word.len - 2];

    // At end of word: consonant-vowel-consonant (but not w,x,Y)
    if (word.len == 2) {
        return !isVowelChar(prev) and isVowelChar(last);
    }

    if (word.len >= 3) {
        const prev2 = word[word.len - 3];
        if (isVowelChar(prev) and !isVowelChar(last)) {
            if (last != 'w' and last != 'x' and last != 'Y') {
                return !isVowelChar(prev2);
            }
        }
    }

    return false;
}

/// Check if word is short (consists only of R1 and ends in short syllable)
fn isShortWord(word: []const u8) bool {
    const r1_pos = getR1(word);
    return r1_pos >= word.len and endsInShortSyllable(word);
}

/// Valid li-ending: c, d, e, g, h, k, m, n, r, t
fn isValidLiEnding(c: u8) bool {
    return c == 'c' or c == 'd' or c == 'e' or c == 'g' or c == 'h' or
        c == 'k' or c == 'm' or c == 'n' or c == 'r' or c == 't';
}

/// Special words that should not be stemmed further after step 1a
fn isSpecialWord(word: []const u8) bool {
    const special_words = [_][]const u8{
        "inning",  "outing", "canning", "herring", "earring",
        "proceed", "exceed", "succeed",
    };

    for (special_words) |special| {
        if (std.mem.eql(u8, word, special)) return true;
    }
    return false;
}

// Tests

test "snowball: basic stemming" {
    var stemmer = Stemmer.init(testing.allocator);

    const tests = [_]struct { word: []const u8, expected: []const u8 }{
        .{ .word = "consign", .expected = "consign" },
        .{ .word = "consigned", .expected = "consign" },
        .{ .word = "consigning", .expected = "consign" },
        .{ .word = "consignment", .expected = "consign" },
        .{ .word = "consist", .expected = "consist" },
        .{ .word = "consisted", .expected = "consist" },
        .{ .word = "consistency", .expected = "consist" },
        .{ .word = "consistent", .expected = "consist" },
        .{ .word = "consistently", .expected = "consist" },
        .{ .word = "consisting", .expected = "consist" },
    };

    for (tests) |t| {
        const result = try stemmer.stem(t.word);
        defer testing.allocator.free(result);
        try testing.expectEqualStrings(t.expected, result);
    }
}

test "snowball: step 0 apostrophes" {
    var stemmer = Stemmer.init(testing.allocator);

    const tests = [_]struct { word: []const u8, expected: []const u8 }{
        .{ .word = "he's", .expected = "he" },
        .{ .word = "it's'", .expected = "it" },
        .{ .word = "boys'", .expected = "boy" },
    };

    for (tests) |t| {
        const result = try stemmer.stem(t.word);
        defer testing.allocator.free(result);
        try testing.expectEqualStrings(t.expected, result);
    }
}

test "snowball: step 1a plurals" {
    var stemmer = Stemmer.init(testing.allocator);

    const tests = [_]struct { word: []const u8, expected: []const u8 }{
        .{ .word = "caresses", .expected = "caress" },
        .{ .word = "ponies", .expected = "poni" },
        .{ .word = "ties", .expected = "tie" },
        .{ .word = "cats", .expected = "cat" },
    };

    for (tests) |t| {
        const result = try stemmer.stem(t.word);
        defer testing.allocator.free(result);
        try testing.expectEqualStrings(t.expected, result);
    }
}

test "snowball: R1/R2 detection" {
    try testing.expectEqual(@as(usize, 5), getR1("beautiful"));
    try testing.expectEqual(@as(usize, 7), getR2("beautiful"));
    try testing.expectEqual(@as(usize, 5), getR1("generation"));
    try testing.expectEqual(@as(usize, 6), getR1("communicate"));
}
