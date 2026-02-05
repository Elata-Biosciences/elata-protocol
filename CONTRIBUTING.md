# Contributing to Elata Protocol

This guide covers everything you need to contribute to the smart contracts.

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) — `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- [Node.js](https://nodejs.org/) v18+
- Git

### Setup

```bash
# Clone your fork
git clone https://github.com/your-username/elata-protocol
cd elata-protocol

# Install dependencies and git hooks
make install

# Build contracts
make build

# Run tests
make test
```

The `make install` command sets up pre-commit hooks that format code and run tests before each commit.

## Development Workflow

### 1. Create a branch

Use descriptive names with prefixes:

```
feature/add-emergency-withdraw
fix/voting-power-calculation
docs/update-deployment-guide
test/add-lotpool-fuzz-tests
```

### 2. Make changes

Edit contracts in `src/`, add tests in `test/`. Run tests frequently:

```bash
# Quick test run
forge test

# Test specific contract
forge test --match-contract VeELTATest

# Test with gas report
make gas-report

# Run all CI checks
make ci
```

### 3. Format and lint

```bash
make fmt        # Format code
make fmt-check  # Check formatting without changes
```

### 4. Commit with conventional commits

```
feat(token): add burn functionality
fix(staking): correct boost calculation for edge case
docs(readme): update deployment instructions
test(lotpool): add fuzz tests for voting
refactor(apps): extract deployment library
```

### 5. Open a pull request

Include in your PR description:
- What changed and why
- How to test it
- Any breaking changes

## Code Style

See [STYLE.md](./STYLE.md) for comprehensive NatSpec conventions and formatting standards.

### Solidity

Follow the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html):

```solidity
// Use explicit imports
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Document public functions with NatSpec
/**
 * @notice Creates a new staking position
 * @param amount ELTA tokens to lock
 * @param duration Lock duration in seconds
 * @return positionId The ID of the created position
 */
function createLock(uint256 amount, uint256 duration) external returns (uint256 positionId) {
    // Implementation
}
```

### Testing

Name tests descriptively:

```solidity
function test_CreateLock_WithMinDuration() public { }
function test_CreateLock_RevertWhen_AmountIsZero() public { }
function testFuzz_CreateLock_AnyValidDuration(uint256 duration) public { }
```

Test both success paths and revert conditions. Add fuzz tests for functions with numeric inputs.

### Custom Errors

Use custom errors instead of require strings:

```solidity
// In src/utils/Errors.sol
error AmountTooLow();
error LockExpired();

// In contract
if (amount < MIN_AMOUNT) revert Errors.AmountTooLow();
```

## Project Structure

```
src/
├── staking/VeELTA.sol          # Vote-escrowed staking
├── experience/ElataPoints.sol  # Reputation system
├── governance/                 # Governor, timelock, funding
├── rewards/                    # Fee distribution
├── apps/                       # App token framework
├── fees/                       # Fee routing infrastructure
├── modules/                    # Airdrops, referrals
├── vesting/                    # Token vesting contracts
└── utils/Errors.sol            # Shared error definitions

lib/ELTA/                       # ELTA token (external dependency)

test/
├── token/ELTATest.t.sol        # Unit tests per contract
├── staking/VeELTATest.t.sol
├── integration/                # Cross-contract tests
└── fuzz/                       # Property-based tests

script/
├── Deploy.sol                  # Main deployment script
└── SeedLocalData.s.sol         # Local test data seeding
```

## Running the Full CI Suite

Before pushing, run the same checks CI will run:

```bash
make ci
```

This runs:
1. `forge fmt --check` — formatting check
2. `forge build` — compilation
3. `forge test` — all tests
4. Gas report generation

## Security Guidelines

When modifying contracts:

- Use OpenZeppelin contracts where possible
- Add reentrancy guards to functions that transfer tokens
- Validate all inputs (zero addresses, array lengths, bounds)
- Consider edge cases in math operations
- Add access control to admin functions
- Write tests for the security properties you're relying on

### Reporting Security Issues

See [SECURITY.md](./SECURITY.md) for our security policy and vulnerability reporting process.

If you find a security vulnerability:

1. Do not open a public issue
2. Email security@elata.bio with details
3. Allow time for a fix before disclosure

## Getting Help

- Check existing [GitHub Issues](https://github.com/Elata-Biosciences/elata-protocol/issues)
- Read the [architecture docs](./docs/ARCHITECTURE.md)
- Ask in the community Discord

## Recognition

Significant contributions may be eligible for:
- ELTA token grants
- Recognition in release notes
- Contributor role in the community

Thanks for contributing.
