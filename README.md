# Elata Protocol

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/Elata-Biosciences/elata-protocol/actions/workflows/ci.yml/badge.svg)](https://github.com/Elata-Biosciences/elata-protocol/actions)
[![Simulation](https://github.com/Elata-Biosciences/elata-protocol/actions/workflows/simulation-ci.yml/badge.svg)](https://github.com/Elata-Biosciences/elata-protocol/actions)
[![Docs](https://img.shields.io/badge/docs-architecture-green)](docs/ARCHITECTURE.md)

Smart contracts for token economics, staking, reputation, and app development funding governance. This repository contains the on-chain infrastructure that coordinates participants in the Elata ecosystem—developers building neurotech applications, users contributing data, and community members providing governance input.

> **Scope**: Token economics, staking, XP reputation, and funding governance. Experiment data contracts (ZORP) live in a separate repository.

## Mechanism Primitives

The protocol implements four core primitives:

**ELTA Token**: ERC20 governance and utility token with a hard cap of 77 million. Used as the quote currency for all bonding curves, staking collateral, and governance participation.

**veELTA Staking**: Users lock ELTA for 7 days to 2 years to receive vote-escrowed ELTA. Longer locks earn up to 2x boost on voting power. veELTA holders receive 15% of all protocol fees.

**XP (ElataPoints)**: Non-transferable, soulbound reputation tokens earned through protocol participation. XP gates early access to new app launches (first 6 hours) and weights votes in funding decisions.

**Bonding Curves**: Constant-product (x·y=k) curves for fair app token distribution. Creators pay 110 ELTA to launch; tokens are split 50% to curve, 25% to team vesting, 25% to ecosystem. Curves graduate to Uniswap LP pairs upon reaching 42,000 ELTA raised.

For formal specifications and equations, see [docs/PROTOCOL_SUMMARY.md](./docs/PROTOCOL_SUMMARY.md).

## Quick Start

Run one command to start a local blockchain with all contracts deployed and seeded with test data:

```bash
bash scripts/dev-local.sh
```

This starts Anvil, deploys all contracts, seeds test users with XP and ELTA, creates sample apps, and generates frontend configuration. Your local environment is ready in about 30 seconds.

Alternatively:

```bash
npm run local:up
```

### Next Steps

View deployed contract addresses:

   ```bash
   cat deployments/local.json
   ```

Connect MetaMask to the local network:
- RPC URL: `http://127.0.0.1:8545`
   - Chain ID: `31337`

See [QUICKSTART.md](./QUICKSTART.md) for the complete setup guide.

## Repository Structure

```
src/
├── staking/        # veELTA time-locked staking
├── experience/     # ElataPoints reputation system
├── governance/     # Governor, Timelock
├── rewards/        # Fee distribution contracts
├── fees/           # Fee routing infrastructure
├── apps/           # App token launch framework
├── modules/        # Airdrops, referrals
├── vesting/        # Token vesting contracts
└── utils/          # Shared utilities

lib/ELTA/           # ELTA token (external dependency)
```

## Core Contracts

| Contract | Purpose | Source |
|----------|---------|--------|
| ELTA | ERC20 governance token with 77M supply cap | [lib/ELTA/src/ELTA.sol](lib/ELTA/src/ELTA.sol) |
| VeELTA | Vote-escrowed staking (7 days to 2 years) | [src/staking/VeELTA.sol](src/staking/VeELTA.sol) |
| ElataPoints | Non-transferable reputation points | [src/experience/ElataPoints.sol](src/experience/ElataPoints.sol) |
| RewardsDistributor | Protocol fee distribution (70/15/15 split) | [src/rewards/RewardsDistributor.sol](src/rewards/RewardsDistributor.sol) |
| ElataGovernor | On-chain governance with 4% quorum | [src/governance/ElataGovernor.sol](src/governance/ElataGovernor.sol) |
| AppFactory | Permissionless app token launches | [src/apps/AppFactory.sol](src/apps/AppFactory.sol) |

## How It Works

The protocol coordinates three activities:

**Staking**: Users lock ELTA tokens to receive veELTA, which grants voting power and a share of protocol revenue. Longer locks (up to 2 years) earn up to 2x boost on voting power.

**Reputation**: Users earn XP through protocol participation—playing apps, submitting data, engaging in governance. XP is non-transferable and determines voting weight in funding decisions.

**Funding**: Each week, the community votes (weighted by XP) to allocate protocol funds to app experiments and development grants. Winners receive ELTA from the treasury.

Protocol revenue flows from app launch fees, trading fees, and tournament rake. The RewardsDistributor splits incoming fees: 70% to app token stakers, 15% to veELTA holders, 15% to treasury.

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) (forge, anvil, cast)
- Node.js v18+

### Commands

```bash
# Install dependencies and set up git hooks
make install

# Build contracts
make build

# Run tests
make test

# Run tests with gas report
make gas-report

# Format code
make fmt

# Run all CI checks before pushing
make ci
```

### Testing and Validation

The protocol includes comprehensive testing at multiple levels:

**Foundry Test Suite**: Unit tests, integration tests, fuzz tests, and invariant tests covering all contract functionality.

```bash
# Run all tests
forge test

# Run specific contract tests
forge test --match-contract ELTATest

# Run invariant tests
forge test --match-path "test/invariants/*"

# Run with verbose output
forge test -vvv
```

**Agent-Based Simulation**: Multi-actor economic simulations powered by AgentForge, running against real contracts deployed on Anvil. Simulations validate fee flows, bonding curve behavior, staking dynamics, and adversarial scenarios.

```bash
# Run smoke tests (fast validation)
cd sim && pnpm install && pnpm run smoke:all

# Run economic scenarios
pnpm run economic:fee-timing

# Full ecosystem simulation with report
pnpm run sim:run
```

Simulation artifacts are uploaded by CI—see [.github/workflows/simulation-ci.yml](.github/workflows/simulation-ci.yml). For detailed simulation documentation, see [sim/README.md](./sim/README.md).

### Deploying to Testnet

```bash
# Set environment variables
export ADMIN_MSIG=0xYourGnosisSafe
export INITIAL_TREASURY=0xYourTreasury
export SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
export ETHERSCAN_API_KEY=YOUR_KEY

# Deploy to Sepolia
npm run deploy:sepolia
```

See [SEPOLIA_DEPLOYMENT_GUIDE.md](./SEPOLIA_DEPLOYMENT_GUIDE.md) for detailed deployment instructions.

## Documentation

| Document | Description |
|----------|-------------|
| [QUICKSTART.md](./QUICKSTART.md) | Local development setup |
| [docs/PROTOCOL_SUMMARY.md](./docs/PROTOCOL_SUMMARY.md) | Protocol summaries and system of equations |
| [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) | System design and contract relationships |
| [docs/TOKENOMICS.md](./docs/TOKENOMICS.md) | ELTA token mechanics and economics |
| [docs/APP_LAUNCH_GUIDE.md](./docs/APP_LAUNCH_GUIDE.md) | Building apps on the protocol |
| [docs/LOCAL_DEVELOPMENT.md](./docs/LOCAL_DEVELOPMENT.md) | Detailed local dev environment |
| [docs/DEPLOYMENT.md](./docs/DEPLOYMENT.md) | Production deployment procedures |
| [docs/xp-system.md](./docs/xp-system.md) | XP distribution architecture |
| [docs/xp-ops.md](./docs/xp-ops.md) | XP operator runbook |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Contribution guidelines |

## Key Parameters

```
ELTA Supply Cap:     77,000,000 tokens
Staking Lock Range:  7 days to 730 days (2 years)
Staking Boost:       1x (min lock) to 2x (max lock)
Governance Quorum:   4% of total supply
Proposal Threshold:  0.1% of total supply (~77,000 ELTA)
Voting Delay:        1 day
Voting Period:       7 days (3 days for emergency proposals)
Trading Fee:         1% (routed to RewardsDistributor)
Revenue Split:       70% app stakers / 15% veELTA / 15% treasury
```

## Security

The contracts are designed with these principles:

- **Non-upgradeable**: All contracts are immutable after deployment
- **Role-based access**: Admin functions require multisig approval
- **Supply cap enforcement**: ELTA cannot exceed 77M tokens
- **Time-locked governance**: 48-hour delay on governance execution
- **No transfer fees on ELTA**: Compatible with standard DeFi infrastructure

Security audit status: Pending external audit before mainnet deployment.

For vulnerability reports, see [SECURITY.md](./SECURITY.md).

## Branches and Releases

| Branch | Purpose | Audit Status |
|--------|---------|--------------|
| `main` | Stable release | Pending external audit |
| `vNext` | Active development | Not audited |

**Deployment tags**: Correspond to on-chain deployments. See `deployments/` for addresses.

**Versioning**: Follows [Semantic Versioning](https://semver.org/). Breaking changes increment major version.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development workflow, code style, and PR guidelines.

```bash
# Quick start for contributors
git clone https://github.com/YOUR_USERNAME/elata-protocol
cd elata-protocol
make install
make ci  # Run all checks before pushing
```

## License

MIT License. See [LICENSE](./LICENSE).

---

For questions, open a GitHub issue or join the community Discord.
