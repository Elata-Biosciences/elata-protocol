# Elata Protocol

Smart contracts for token economics, staking, reputation, and research funding governance. This repository contains the on-chain infrastructure that coordinates participants in the Elata ecosystem—developers building neurotech applications, researchers conducting studies, and community members contributing data and governance input.

> **Scope**: Token economics, staking, XP reputation, and funding governance. Experiment data contracts (ZORP) live in a separate repository.

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

Start the frontend (in a separate terminal):

   ```bash
   cd ../elata-appstore
   npm run local:full
   ```

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
├── token/          # ELTA governance token
├── staking/        # veELTA time-locked staking
├── experience/     # ElataPoints reputation system
├── governance/     # Governor, Timelock
├── rewards/        # Fee distribution contracts
├── fees/           # Fee routing infrastructure
├── apps/           # App token launch framework
└── utils/          # Shared utilities
```

## Core Contracts

| Contract | Purpose | Source |
|----------|---------|--------|
| ELTA | ERC20 governance token with 77M supply cap | [src/token/ELTA.sol](src/token/ELTA.sol) |
| VeELTA | Vote-escrowed staking (7 days to 2 years) | [src/staking/VeELTA.sol](src/staking/VeELTA.sol) |
| ElataPoints | Non-transferable reputation points | [src/experience/ElataPoints.sol](src/experience/ElataPoints.sol) |
| RewardsDistributor | Protocol fee distribution (70/15/15 split) | [src/rewards/RewardsDistributor.sol](src/rewards/RewardsDistributor.sol) |
| ElataGovernor | On-chain governance with 4% quorum | [src/governance/ElataGovernor.sol](src/governance/ElataGovernor.sol) |
| AppFactory | Permissionless app token launches | [src/apps/AppFactory.sol](src/apps/AppFactory.sol) |

## How It Works

The protocol coordinates three activities:

**Staking**: Users lock ELTA tokens to receive veELTA, which grants voting power and a share of protocol revenue. Longer locks (up to 2 years) earn up to 2x boost on voting power.

**Reputation**: Users earn XP through protocol participation—playing apps, submitting data, engaging in governance. XP is non-transferable and determines voting weight in funding decisions.

**Funding**: Each week, the community votes (weighted by XP) to allocate protocol funds to research proposals and development grants. Winners receive ELTA from the treasury.

Protocol revenue flows from app store fees, trading fees, and tournament rake. The RewardsDistributor splits incoming fees: 70% to app token stakers, 15% to veELTA holders, 15% to treasury.

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) (forge, anvil, cast)
- Node.js v18+
- Docker Desktop (for the App Store's Postgres database)

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

### Testing

The test suite includes unit tests, integration tests, and fuzz tests:

```bash
# Run all tests
forge test

# Run specific contract tests
forge test --match-contract ELTATest

# Run with verbose output
forge test -vvv
```

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
