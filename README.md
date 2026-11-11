# stemmer-zig

Try the [self-contained task](docs/SELF_SERVE.md): `zig build demo`.

Porter (1980) and Snowball (Porter2) English stemmers in Zig 0.16.

Extracted from a private research repo; the algorithms are unchanged from
that source, which implemented Porter's published algorithm directly
(reference: https://tartarus.org/martin/PorterStemmer/). What changed in
extraction: migration to Zig 0.16 APIs, and correction of fifteen legacy
test expectations that had never executed in the source repo (its build
never wired them in) and asserted *step-level* rule-table transforms
against the *full* pipeline — every corrected value was refereed against
NLTK's PorterStemmer in both `ORIGINAL_ALGORITHM` and default modes, which
agree with this implementation on all fifteen.

## What ships

- `porter` — Porter 1980, steps 1a–5b with measure/CVC logic. Allocating
  API: `Stemmer.init(allocator)`, `stem(word) ![]const u8` (caller frees).
- `snowball` — Snowball/Porter2: step-0 apostrophe handling, R1/R2 region
  detection.
- `stemmer-vocab` (`zig build vocab -- <porter|snowball>`) — emits
  `word\tstem` TSV over the committed Brown-vocabulary fixture.

## Verification

- 20 unit tests (`zig build test`), including a generated 2×208-pair
  golden-sample regression sourced from the committed full-vocabulary
  goldens.
- `tests/fixtures/brown_vocab.txt` — 41,434 unique lowercase `[a-z]+`
  word types from the Brown Corpus (provenance pipeline in the file
  header). `tests/golden/{porter,snowball}_brown.tsv` — full stem output
  over that vocabulary, verified byte-identical across runs.
- NLTK reference agreement over all 41,434 words (2026-06-12, NLTK
  PorterStemmer / SnowballStemmer("english")):
  - Porter vs NLTK `ORIGINAL_ALGORITHM`: **99.32%** (41,153/41,434)
  - Porter vs NLTK default (NLTK extensions): 97.31%
  - Snowball vs NLTK Snowball: **99.24%** (41,118/41,434)

  The residual ~0.7% disagreements are boundary-condition classes
  (e.g. `-ement` handling: this implementation stems `agreement → agreem`
  where NLTK-original keeps `agreement`), documented rather than chased;
  they are stable and covered by the committed goldens.

## Scope limits, stated plainly

- English only. ASCII only — input is lowercased with `std.ascii.toLower`;
  bytes ≥ 0x80 pass through untouched, so non-ASCII words are not
  meaningfully stemmed.
- Words shorter than 3 bytes are returned unchanged (Porter's convention).
- The allocating per-word API is convenient, not fast; no SIMD, no arena
  reuse across calls. Benchmark before using in a hot loop.
- Not a lemmatizer: stems are equivalence-class keys, not dictionary forms
  (`poni`, `relat` are correct outputs).

## Roadmap

- `stemmer-ex`: a pure-Elixir mirror with the committed Brown golden TSVs
  as the cross-runtime conformance suite (total string equality over all
  41,434 words) — the same bilingual verification pattern as the
  throughline env suite. Not built yet.

## License

AGPL-3.0-or-later.
