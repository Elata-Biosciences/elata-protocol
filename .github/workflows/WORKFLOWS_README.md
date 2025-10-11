# GitHub Actions Workflows

This directory contains CI/CD workflows for the Elata Protocol.

## Workflows

### ci.yml - Main CI Pipeline

**Triggers:** Push to main/develop, Pull Requests

**Jobs:**
1. **Foundry Tests** - Runs the full test suite (422 tests)
2. **Code Quality** - Checks formatting and generates gas report
3. **Test Coverage** - Generates test coverage (non-blocking due to compiler limitations)

**Status:** All critical jobs must pass for CI to succeed.

### test.yml - Simple Test Workflow

**Triggers:** All pushes

**Jobs:**
1. **Foundry project** - Basic build and test check

### pr-checks.yml - Pull Request Validation

**Triggers:** Pull Requests only

**Jobs:**
1. **Code Formatting** - Verifies code is formatted
2. **Build** - Compiles contracts
3. **Tests** - Runs test suite
4. **Security Tests** - Runs security-focused tests
5. **Gas Report** - Posts gas usage as PR comment
6. **Coverage** - Generates coverage report
7. **Summary** - Aggregates all check results

## Known Issues

### Coverage Job

**Issue:** The coverage job may fail with "stack too deep" errors.

**Root Cause:** `forge coverage` disables optimizer and `via_ir` to generate accurate coverage, but `AppDeploymentLib.sol` requires these optimizations to compile.

**Current Solution:** The coverage job is marked as `continue-on-error: true`, making it non-blocking.

**Future Solutions:**
- Refactor AppDeploymentLib to reduce complexity
- Exclude specific files from coverage
- Wait for Foundry coverage improvements

**Impact:** CI passes even if coverage fails. Tests and builds are not affected.

## Workflow Best Practices

### For Contributors

Before pushing:
```bash
# Run all CI checks locally
make ci

# Or step by step:
make fmt-check  # Check formatting
make build      # Build contracts
make test       # Run tests
```

### For Maintainers

**Adding new workflows:**
1. Create `.yml` file in `.github/workflows/`
2. Test locally with act: `act -l`
3. Start with minimal jobs, expand gradually
4. Use `continue-on-error: true` for optional checks

**Modifying existing workflows:**
1. Test changes on a feature branch first
2. Check workflow syntax: `act -l`
3. Monitor first run closely
4. Update this README with changes

## Debugging CI Failures

### Build Failures

**Check:**
1. Do submodules exist? (`git submodule status`)
2. Are remappings correct? (Check `remappings.txt`)
3. Is foundry.toml profile configured? (Check `FOUNDRY_PROFILE` env)

**Fix locally:**
```bash
forge clean
forge build --sizes
```

### Test Failures

**Check:**
1. Do tests pass locally? (`forge test -vv`)
2. Are there environment differences? (solc version, etc.)

**Fix locally:**
```bash
FOUNDRY_PROFILE=ci forge test -vv
```

### Coverage Failures

**Expected:** Coverage may fail due to complex contracts (non-blocking).

**If it should pass:**
```bash
forge coverage --ir-minimum --report lcov
```

## Workflow Performance

- **Average CI time:** ~30-60 seconds
- **Longest job:** Foundry Tests (~15-20s)
- **Parallel jobs:** Yes (test, lint, coverage run in parallel)

## Security

**Secrets used:**
- `CODECOV_TOKEN` - For uploading coverage reports (optional)

**Permissions:**
- Workflows have read-only access to repository
- No write permissions to prevent accidental changes

## Contact

Questions about CI/CD? Contact the team or open an issue.

