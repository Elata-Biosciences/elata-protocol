# Fuzzing Corpus

This directory contains corpus data for coverage-guided fuzzing in Foundry.

## Directory Structure

```
corpus/
├── fuzz/              # Corpus for fuzz tests
│   └── <test_name>/   # Per-test corpus directories
├── invariant/         # Corpus for invariant tests
│   └── <test_name>/   # Per-test corpus directories
└── README.md          # This file
```

## How Coverage-Guided Fuzzing Works

Foundry's coverage-guided fuzzing automatically:

1. **Saves successful call sequences** - When a fuzz test finds inputs that increase code coverage, those inputs are saved to the corpus
2. **Mutates saved inputs** - Future runs load saved inputs and mutate them to explore new code paths
3. **Persists failures** - When a test fails, the failing input is saved for reproduction

## Configuration

The corpus directories are configured in `foundry.toml`:

```toml
[fuzz]
corpus_dir = "corpus/fuzz"
failure_persist_dir = "cache/fuzz"  # Failed inputs saved here

[invariant]
corpus_dir = "corpus/invariant"
```

## Usage

### Running with Corpus

Simply run your tests as normal:

```bash
# Fuzz tests will use corpus/fuzz/
forge test --match-path "test/fuzz/*" -vvv

# Invariant tests will use corpus/invariant/
forge test --match-path "test/invariants/*" -vvv
```

### Building Up the Corpus

The corpus grows automatically as you run tests. For more thorough corpus building:

```bash
# Run with more iterations to build corpus
forge test --match-path "test/fuzz/*" --fuzz-runs 10000 -vvv
```

### Reproducing Failures

Failed inputs are saved to `cache/fuzz/`. To reproduce:

1. Find the failing input in `cache/fuzz/`
2. The file contains the seed that caused the failure
3. Re-run with that seed to reproduce

### Cleaning the Corpus

To start fresh:

```bash
rm -rf corpus/fuzz/*
rm -rf corpus/invariant/*
rm -rf cache/fuzz/*
```

## Best Practices

1. **Commit the corpus** - Including corpus in version control helps the whole team benefit from discovered paths
2. **Run extended fuzzing in CI** - Use higher iteration counts in CI to expand the corpus
3. **Review new corpus entries** - Significant corpus growth may indicate unexplored code paths
4. **Seed the corpus** - For known edge cases, you can manually add inputs to the corpus

## Files in Corpus

Each corpus file is a binary blob containing the input data that achieved new coverage. Foundry handles serialization/deserialization automatically.
