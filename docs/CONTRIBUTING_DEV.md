# Contributing to Elata Protocol - Developer Guide

Thank you for your interest in contributing! This guide will help you set up your development environment and follow our best practices.

## Getting Started

### 1. Initial Setup

```bash
# Clone the repository
git clone https://github.com/Elata-Biosciences/elata-protocol.git
cd elata-protocol

# Install dependencies and setup hooks
make install

# Or manually:
forge install
bash scripts/setup-hooks.sh
```

### 2. Development Workflow

#### Quick Commands

We provide a Makefile for common tasks:

```bash
make help           # Show all available commands
make build          # Build contracts
make test           # Run tests
make test-v         # Run tests with verbose output
make fmt            # Format code
make fmt-check      # Check formatting
make coverage       # Generate coverage report
make gas-report     # Generate gas usage report
make ci             # Run all CI checks locally
```

#### Before Committing

The pre-commit hook will automatically:
1. Format your code with `forge fmt`
2. Build the contracts
3. Run the test suite

If any step fails, the commit will be rejected.

**To skip hooks (NOT RECOMMENDED):**
```bash
git commit --no-verify
```

#### Before Pushing

The pre-push hook will run comprehensive checks:
1. Verify code formatting
2. Build with size checks
3. Run full test suite
4. Generate gas report
5. Run security checks

### 3. Code Style Guide

#### Solidity

- Follow the official [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- Use `forge fmt` for consistent formatting (runs automatically on commit)
- Maximum line length: 120 characters
- Use descriptive variable names
- Add NatSpec comments for all public/external functions

Example:
```solidity
/**
 * @notice Stakes tokens into the vault
 * @param amount The amount of tokens to stake
 * @return shares The amount of shares minted
 */
function stake(uint256 amount) external returns (uint256 shares) {
    require(amount > 0, "Cannot stake zero");
    // Implementation...
}
```

#### Testing

- Write comprehensive tests for all functionality
- Use descriptive test names: `test_FunctionName_Scenario_ExpectedOutcome`
- Group related tests with comments
- Include both positive and negative test cases
- Add fuzz tests for functions with numeric inputs

Example:
```solidity
function test_stake_WithValidAmount_IncreasesBalance() public {
    // Setup
    uint256 stakeAmount = 100 ether;
    
    // Execute
    vault.stake(stakeAmount);
    
    // Assert
    assertEq(vault.balanceOf(user), stakeAmount);
}
```

### 4. Git Workflow

#### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `refactor/description` - Code refactoring
- `docs/description` - Documentation updates
- `test/description` - Test additions/updates

#### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Formatting, missing semicolons, etc.
- `refactor`: Code restructuring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

Examples:
```bash
feat(staking): add emergency withdrawal function
fix(vault): correct share calculation rounding error
docs(readme): update deployment instructions
test(governance): add fuzz tests for voting
```

#### Pull Request Process

1. Create a feature branch from `develop`
2. Make your changes following the style guide
3. Ensure all tests pass (`make test`)
4. Run CI checks locally (`make ci`)
5. Push your branch and create a PR
6. Fill out the PR template completely
7. Wait for CI checks to pass
8. Request review from maintainers
9. Address review feedback
10. Maintainers will merge when approved

### 5. Testing Best Practices

#### Running Tests

```bash
# Run all tests
make test

# Run specific test file
forge test --match-path test/unit/ELTA.t.sol

# Run specific test
forge test --match-test test_mint_IncreasesBalance

# Run with verbose output
make test-v

# Run with trace output
forge test -vvv

# Run with gas reporting
make gas-report
```

#### Test Coverage

Aim for >90% test coverage:

```bash
# Generate coverage report
make coverage

# View coverage in browser (requires lcov)
genhtml lcov.info --branch-coverage --output-dir coverage
open coverage/index.html
```

#### Security Testing

Always run security tests before submitting:

```bash
# Run security test suite
forge test --match-contract Security

# Run security checks
make security-check
```

### 6. Common Issues and Solutions

#### Issue: Tests fail on commit

**Solution:** Run tests manually to see detailed output:
```bash
forge test -vv
```

#### Issue: Formatting check fails

**Solution:** Format your code:
```bash
make fmt
git add -u
git commit --amend --no-edit
```

#### Issue: Contract size too large

**Solution:**
- Extract complex view functions to a separate views contract
- Move logic to libraries
- Optimize storage layout
- Consider deploying to L2

#### Issue: Gas optimizations needed

**Solution:**
```bash
# Compare gas usage
forge snapshot
# Make changes
forge snapshot --diff

# Generate detailed gas report
make gas-report
```

### 7. CI/CD Pipeline

Our CI/CD pipeline runs on every push and PR:

1. **Formatting Check** - Verifies code is properly formatted
2. **Build** - Compiles all contracts
3. **Tests** - Runs full test suite
4. **Security Tests** - Runs security-focused tests
5. **Gas Report** - Generates gas usage report
6. **Coverage** - Uploads coverage to Codecov

Make sure all checks pass before merging.

### 8. Release Process

1. All changes merged to `develop` branch
2. Create release PR from `develop` to `main`
3. Update version numbers and CHANGELOG
4. Run full audit checklist
5. Get approval from core team
6. Merge to `main` and tag release
7. Deploy to production

### 9. Getting Help

- 💬 Join our [Discord](https://discord.gg/elata)
- 📧 Email: dev@elata.bio
- 📖 Read the [full documentation](./docs/)
- 🐛 [Report bugs](https://github.com/Elata-Biosciences/elata-protocol/issues)

## Code of Conduct

Please be respectful and constructive in all interactions. We are building together!

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

