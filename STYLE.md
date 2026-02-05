# Code Style Guide

This guide documents NatSpec conventions and formatting standards for Elata Protocol contracts.

## Solidity File Structure

Every Solidity file follows this order:

1. **SPDX license identifier** (required, first line)
2. **Pragma statement**
3. **Imports** (explicit named imports preferred)
4. **Contract NatSpec block**
5. **Contract declaration**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ContractName
 * @author Elata Biosciences
 * @notice One-sentence user-facing summary
 * @dev Technical details and implementation notes
 * @custom:security-contact security@elata.bio
 */
contract ContractName is ERC20, AccessControl {
    // ...
}
```

## NatSpec Header Template

### Core Contracts

All protocol contracts include these NatSpec tags:

```solidity
/**
 * @title ContractName
 * @author Elata Biosciences
 * @notice One-sentence user-facing summary
 * @dev Detailed notes covering:
 *      - Key invariants
 *      - Trust model / access control
 *      - External dependencies
 *      - Non-obvious assumptions
 * @custom:security-contact security@elata.bio
 */
```

### Libraries

```solidity
/**
 * @title LibraryName
 * @notice Brief description of purpose
 * @dev Implementation notes if needed
 * @custom:security-contact security@elata.bio
 */
```

## Function Documentation

### Public/External Functions

Document all public and external functions with:

- `@notice` — User-facing description
- `@dev` — Implementation details (if non-obvious)
- `@param` — All parameters
- `@return` — All return values

```solidity
/**
 * @notice Creates a new staking position
 * @dev Locks ELTA tokens for the specified duration to mint veELTA
 * @param amount ELTA tokens to lock
 * @param duration Lock duration in seconds (MIN_LOCK to MAX_LOCK)
 * @return positionId The ID of the created position
 */
function createLock(uint256 amount, uint256 duration) external returns (uint256 positionId) {
    // Implementation
}
```

### Interface Implementations

Use `@inheritdoc` for functions that implement an interface:

```solidity
/// @inheritdoc IERC20
function transfer(address to, uint256 amount) public override returns (bool) {
    // Implementation
}
```

## Section Comments

Use consistent section headers within contracts:

```solidity
// =========== Errors ===========
error ZeroAddress();
error InvalidAmount();

// =========== Events ===========
event Deposited(address indexed user, uint256 amount);

// =========== State ===========
uint256 public totalDeposits;

// =========== Constructor ===========
constructor(address _token) { }

// =========== Core Functions ===========
function deposit(uint256 amount) external { }

// =========== Admin Functions ===========
function pause() external onlyAdmin { }

// =========== View Functions ===========
function getBalance(address user) external view returns (uint256) { }
```

## Naming Conventions

### Variables

- State variables: `camelCase`
- Constants: `UPPER_SNAKE_CASE`
- Private variables: `_prefixedWithUnderscore`
- Immutables: `camelCase` or `UPPER_SNAKE_CASE` for primitive types

```solidity
uint256 public constant MAX_SUPPLY = 77_000_000e18;
uint256 public totalStaked;
address private _admin;
IERC20 public immutable ELTA;
```

### Functions

- Public/external: `camelCase`
- Internal/private: `_prefixedWithUnderscore`

### Events

- Past tense for actions that occurred: `Deposited`, `Withdrawn`, `Updated`
- Or present for state changes: `Transfer`, `Approval`

### Errors

- Descriptive noun or adjective phrases: `ZeroAddress`, `InvalidAmount`, `Unauthorized`
- Can include context: `InsufficientBalance`, `LockNotExpired`

## Import Style

Use explicit named imports rather than wildcard imports:

```solidity
// Good
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Avoid
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
```

## Test Naming

Name tests descriptively:

```solidity
function test_CreateLock_WithMinDuration() public { }
function test_CreateLock_RevertWhen_AmountIsZero() public { }
function testFuzz_CreateLock_AnyValidDuration(uint256 duration) public { }
```

## Custom Errors

Use custom errors instead of require strings:

```solidity
// In contract or shared Errors.sol
error AmountTooLow();
error LockExpired();

// Usage
if (amount < MIN_AMOUNT) revert AmountTooLow();
```

## What NOT to Do

- **No ASCII art in Solidity files** — Keep contract headers clean and professional
- **No personal GitHub handles or ENS names** in contract headers — Use organizational authorship ("Elata Biosciences")
- **No HTML or markdown in NatSpec** — These won't render in block explorers or documentation generators
- **No wildcard imports** — Always use explicit named imports
- **No require strings for errors** — Use custom errors for gas efficiency and clarity

## Formatting

Run `forge fmt` before committing. The project uses Foundry's default formatter.

```bash
# Format all files
make fmt

# Check formatting without changes
make fmt-check
```

## References

- [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- [NatSpec Format](https://docs.soliditylang.org/en/latest/natspec-format.html)
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) for examples
