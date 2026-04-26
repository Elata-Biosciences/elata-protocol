# Elata Protocol

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/Elata-Biosciences/elata-protocol/actions/workflows/ci.yml/badge.svg)](https://github.com/Elata-Biosciences/elata-protocol/actions)
[![Simulation](https://github.com/Elata-Biosciences/elata-protocol/actions/workflows/simulation-ci.yml/badge.svg)](https://github.com/Elata-Biosciences/elata-protocol/actions)
[![Docs](https://img.shields.io/badge/docs-architecture-green)](docs/ARCHITECTURE.md)

Smart contracts for app-token launches, bonding-curve distribution, fee routing, staking, and governance in Elata.

> Scope: on-chain protocol contracts only. Product/frontend docs live in the separate `docs` and app repositories.

## Mechanism Primitives

The current system is organized around these primitives:

**ELTA Token**  
Fixed-supply ERC20 (`77,000,000`) minted once at deployment to treasury.

**veELTA Staking**  
Vote-escrow token from locking ELTA (`7` to `730` days) with linear boost from `1x` to `2x`.

**App Launch + Bonding Curve**  
`AppFactory` launches app stacks. Each launch costs `110 ELTA` (`100` curve seed + `10` launch fee). App token supply is `10,000,000` split `50/25/25` across curve/vesting/ecosystem. Curve graduation target is `42,000 ELTA`.

**Fee Pipeline (V2)**  
`FeeCollector` accounts by `(appId, feeKind, asset)`, and `FeeSwapper` routes:
- `LAUNCH_FEE` -> `100%` treasury
- App revenue kinds (`TRADING_FEE`, `TRANSFER_TAX`, etc.) -> contributors + treasury (default `80/20`)
- Paused app -> `100%` treasury

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
├── apps/           # AppFactory, AppToken, AppBondingCurve, modules
├── contributors/   # ContributorSplit contracts
├── core/           # Protocol configuration
├── experience/     # ElataPoints reputation system
├── fees/           # FeeCollector, FeeSwapper, FeeManager, TreasuryUSDCVault
├── governance/     # Governor, Timelock
├── registry/       # AppRegistry
├── staking/        # veELTA time-locked staking
├── vesting/        # App vesting and ecosystem vaults
└── utils/          # Shared utilities/errors

lib/ELTA/           # ELTA token (external dependency)
```

## Core Contracts

| Contract | Purpose | Source |
|----------|---------|--------|
| ELTA | Fixed-supply ERC20 (`77M`) | [lib/ELTA/src/ELTA.sol](lib/ELTA/src/ELTA.sol) |
| VeELTA | Vote-escrowed staking (7 days to 2 years) | [src/staking/VeELTA.sol](src/staking/VeELTA.sol) |
| ElataPoints | Non-transferable reputation points | [src/experience/ElataPoints.sol](src/experience/ElataPoints.sol) |
| AppFactory | App registration + token launch lifecycle | [src/apps/AppFactory.sol](src/apps/AppFactory.sol) |
| AppBondingCurve | Constant-product launch curve + graduation | [src/apps/AppBondingCurve.sol](src/apps/AppBondingCurve.sol) |
| FeeCollector | Fee accounting + permissionless sweeping | [src/fees/FeeCollector.sol](src/fees/FeeCollector.sol) |
| FeeSwapper | Final fee routing and optional swaps | [src/fees/FeeSwapper.sol](src/fees/FeeSwapper.sol) |
| AppRegistry | Canonical app ownership and split registry | [src/registry/AppRegistry.sol](src/registry/AppRegistry.sol) |

## How It Works

1. **Register app** in `AppRegistry` and deploy `ContributorSplit`.
2. **Launch token** for that app: deploy token, curve, vesting, ecosystem vault.
3. **Sell on curve** while active (`x*y=k`) until graduation target/deadline.
4. **Graduate to Uniswap V2** and lock LP.
5. **Route fees through V2 pipeline** (`FeeCollector -> FeeSwapper`) using explicit `FeeKind`.

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

# Run invariant/fuzz suites (targeted)
forge test --match-path "test/invariants/*.t.sol" -vvv

# Run key recent-change suites (targeted)
forge test --match-path "test/apps/AppFactoryTwoPhase.t.sol" -vvv
forge test --match-path "test/apps/AppRegistry.t.sol" -vvv

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
# Build linked AgentForge + install sim deps
pnpm -C ../agentforge build
cd sim && pnpm install

# Run protocol fast lane (recommended PR validation)
pnpm run protocol:fast
pnpm run results:validate:fast

# Run balanced lane (broad protocol behavior validation)
pnpm run protocol:balanced
pnpm run results:validate:balanced

# Open Studio UI against existing simulation runs
pnpm run sim:studio:open

# LLM gossip exploration (uses OPENAI_API_KEY from env by default)
export OPENAI_API_KEY="..."
export OPENAI_MODEL="gpt-4o-mini"
pnpm run sim:llm:adversarial-rumor

# Run economic scenarios
pnpm run economic:fee-timing

# Full ecosystem simulation with report
pnpm run sim:run
```

Simulation artifacts are uploaded by CI—see [.github/workflows/simulation-ci.yml](.github/workflows/simulation-ci.yml). For detailed simulation documentation, see [sim/README.md](./sim/README.md).

Simulation runs now include notebook-style Studio reports with markdown narrative, transforms, ML blocks, and charts/tables. To edit user-facing explanations for a scenario, update its `studio.report` markdown content (typically via `createNotebookReport` in `sim/lib/studio-report.ts`).

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
| [docs/APP_DEVELOPER_GUIDE.md](./docs/APP_DEVELOPER_GUIDE.md) | Progressive protocol guide for app developers |
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
App Launch Cost:     110 ELTA (100 seed + 10 launch fee)
App Token Supply:    10,000,000 tokens
Launch Allocation:   50% curve / 25% vesting / 25% ecosystem
Graduation Target:   42,000 ELTA
LP Lock Duration:    730 days
Staking Lock Range:  7 days to 730 days (2 years)
Staking Boost:       1x (min lock) to 2x (max lock)
Governance Quorum:   4% of total supply
Proposal Threshold:  0.1% of total supply (~77,000 ELTA)
Voting Delay:        1 day
Voting Period:       7 days (3 days for emergency proposals)
Trade Fee Baseline:  1% (`AppFeeRouter.feeBps`, configurable)
V2 Fee Routing:      LAUNCH_FEE -> 100% treasury; app revenue -> default 80/20 contributors/treasury
```

## Security

The contracts are designed with these principles:

- **Non-upgradeable**: All contracts are immutable after deployment
- **Role-based access**: Admin functions require multisig approval
- **Supply cap enforcement**: ELTA is fixed-supply and minted once
- **Time-locked governance**: 48-hour delay on governance execution
- **LP lock on graduation**: liquidity is locked per app on graduation

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

## 💰 Bounty Contribution

- **Task:** Pre-contest audit triage — governance access control patterns
- **Reward:** $1500
- **Source:** GitHub-Bounty
- **Date:** 2026-04-27

