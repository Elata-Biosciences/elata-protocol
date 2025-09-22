# Contributing to Elata Protocol

We welcome contributions from the community! This guide will help you get started with contributing to the Elata Protocol.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Process](#development-process)
- [Pull Request Guidelines](#pull-request-guidelines)
- [Testing](#testing)
- [Code Style](#code-style)
- [Security](#security)

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct. We are committed to providing a welcoming and inclusive environment for all contributors.

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) - Ethereum development toolkit
- [Git](https://git-scm.com/) - Version control
- [Node.js](https://nodejs.org/) (optional, for frontend integration)

### Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/your-username/elata-protocol
   cd elata-protocol
   ```
3. Install dependencies:
   ```bash
   forge install
   ```
4. Build the project:
   ```bash
   forge build
   ```
5. Run tests to ensure everything works:
   ```bash
   forge test
   ```

## Development Process

### Branch Naming

Use descriptive branch names that follow this pattern:
- `feature/description-of-feature`
- `fix/description-of-fix`
- `docs/description-of-docs-change`
- `test/description-of-test-addition`

### Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
type(scope): description

[optional body]

[optional footer]
```

Examples:
- `feat(token): add burn functionality to ELTA token`
- `fix(staking): correct voting power calculation in VeELTA`
- `docs(readme): update installation instructions`
- `test(lotpool): add comprehensive fuzz testing`

### Development Workflow

1. Create a new branch from `main`
2. Make your changes
3. Add tests for new functionality
4. Ensure all tests pass
5. Update documentation if needed
6. Submit a pull request

## Pull Request Guidelines

### Before Submitting

- [ ] All tests pass (`forge test`)
- [ ] Code follows style guidelines
- [ ] Documentation is updated
- [ ] Commit messages follow conventions
- [ ] No merge conflicts with main branch

### PR Description Template

```markdown
## Description
Brief description of changes made.

## Type of Change
- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Fuzz tests added/updated
- [ ] All tests pass

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No new warnings introduced
```

## Testing

### Test Categories

1. **Unit Tests**: Test individual contract functions
   ```bash
   forge test --match-contract ELTATest
   ```

2. **Integration Tests**: Test multi-contract interactions
   ```bash
   forge test --match-contract ProtocolIntegrationTest
   ```

3. **Fuzz Tests**: Property-based testing with random inputs
   ```bash
   forge test --match-test testFuzz_
   ```

### Writing Tests

- Use descriptive test names: `test_RevertWhen_InvalidInput()`
- Test both success and failure cases
- Include edge cases and boundary conditions
- Add fuzz tests for functions with numeric inputs
- Use appropriate assertions and error checking

### Test Structure

```solidity
function test_DescriptiveTestName() public {
    // Setup
    uint256 amount = 1000 ether;
    
    // Action
    vm.prank(user);
    contract.someFunction(amount);
    
    // Assertions
    assertEq(contract.balance(), amount);
}
```

## Code Style

### Solidity Style Guide

We follow the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html) with these additions:

- Use explicit imports: `import {Contract} from "./Contract.sol";`
- Group imports by category (external, internal)
- Use NatSpec documentation for all public functions
- Maximum line length: 100 characters
- Use descriptive variable names
- Include error handling with custom errors

### Documentation Standards

- All public functions must have NatSpec comments
- Include `@param` and `@return` descriptions
- Add `@notice` for user-facing functions
- Use `@dev` for developer notes

Example:
```solidity
/**
 * @notice Creates a new lock for the specified amount and duration
 * @param amount The amount of ELTA tokens to lock
 * @param lockDuration The duration of the lock in seconds
 * @dev Lock duration must be between MIN_LOCK and MAX_LOCK
 */
function createLock(uint256 amount, uint256 lockDuration) external {
    // Implementation
}
```

## Security

### Security Guidelines

- Follow the [ConsenSys Smart Contract Best Practices](https://consensys.github.io/smart-contract-best-practices/)
- Use OpenZeppelin contracts when possible
- Implement proper access controls
- Add reentrancy guards where needed
- Validate all inputs
- Use safe math operations (Solidity 0.8+)

### Reporting Security Issues

If you discover a security vulnerability, please:

1. **DO NOT** open a public issue
2. Email security@elata.bio with details
3. Allow time for the issue to be addressed before disclosure

## Getting Help

- Join our [Discord](https://discord.gg/elata) for community support
- Check existing issues and discussions on GitHub
- Read the documentation at [docs.elata.bio](https://docs.elata.bio)

## Recognition

Contributors will be recognized in our documentation and may be eligible for:
- ELTA token rewards for significant contributions
- Recognition in project credits
- Invitation to contributor events

Thank you for contributing to Elata Protocol! 🧠⚡
