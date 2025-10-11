# Git Hooks

This directory contains Git hooks that help maintain code quality and prevent CI/CD failures.

## Setup

Run the setup script to configure these hooks:

```bash
bash scripts/setup-hooks.sh
# or
make setup-hooks
```

## Available Hooks

### pre-commit

Runs automatically before every commit:

1. **Format Check**: Runs `forge fmt` to ensure code is properly formatted
2. **Build Check**: Verifies contracts compile successfully
3. **Quick Tests**: Runs the test suite to catch issues early

If any step fails, the commit will be rejected.

**Skip hook (not recommended):**
```bash
git commit --no-verify
```

### pre-push

Runs automatically before pushing to remote:

1. **Format Verification**: Ensures code is formatted
2. **Build with Size Check**: Builds contracts and shows sizes
3. **Full Test Suite**: Runs all tests with verbose output
4. **Gas Report**: Generates gas usage report
5. **Security Checks**: Runs security verification scripts

**Skip hook (not recommended):**
```bash
git push --no-verify
```

## Benefits

✅ **Catch Issues Early**: Find problems before CI/CD runs
✅ **Consistent Code Style**: Automatic formatting ensures uniformity
✅ **Faster Feedback**: Get immediate feedback on code quality
✅ **Prevent CI Failures**: Catch formatting and test issues locally
✅ **Save Time**: Avoid back-and-forth with CI/CD

## Troubleshooting

### Hook not running

Check if hooks are configured:
```bash
git config core.hooksPath
# Should output: .githooks
```

Re-run setup if needed:
```bash
bash scripts/setup-hooks.sh
```

### Hook failing unexpectedly

Run the commands manually to see detailed output:
```bash
forge fmt --check
forge build
forge test -vv
```

### Temporarily disable hooks

Only use this if absolutely necessary:
```bash
git commit --no-verify
git push --no-verify
```

## Updating Hooks

If you modify hooks, ensure they remain executable:
```bash
chmod +x .githooks/pre-commit .githooks/pre-push
```

