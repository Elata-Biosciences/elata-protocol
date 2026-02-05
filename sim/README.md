# Elata Protocol Simulation

Agent-based economic simulations powered by [AgentForge](https://github.com/Elata-Biosciences/agentforge), running against real Elata Protocol contracts deployed on Anvil.

## Overview

The simulation framework validates protocol economics by deploying actual contracts to a local Anvil instance and executing multi-agent scenarios. Unlike mock-based testing, these simulations exercise real bytecode and verify mechanism behavior under realistic conditions.

**Key Features:**
- Real contract deployment via Foundry
- Multi-agent scenarios with diverse behavior profiles
- Economic stress testing and adversarial validation
- Automated metrics collection and reporting

## Quick Start

```bash
# Install dependencies
pnpm install

# Run smoke tests (validates basic functionality)
pnpm run smoke:all
```

## Three-Tier Simulation Guide

Choose the appropriate tier based on your time and validation needs:

### Tier 1: Fast Validation (2-5 minutes)

Quick smoke tests to verify basic protocol functionality. Run these before commits or after contract changes.

```bash
pnpm run smoke:all
```

**What it tests:**
- Single agent operations
- App creation and deployment
- Token buying on bonding curves
- Fee collection mechanics

**Output:** Pass/fail status with basic metrics.

### Tier 2: Economic Scenarios (10-15 minutes)

Medium-depth scenarios that validate economic assumptions and adversarial resistance.

```bash
# Fee timing and MEV resistance
pnpm run economic:fee-timing

# Governance attack scenarios
pnpm run economic:governance-attack

# Whale accumulation dynamics
pnpm run economic:whale

# Run all economic scenarios
pnpm run economic:all
```

**What it tests:**
- Fee distribution timing edge cases
- Governance manipulation resistance
- Concentration risk dynamics
- Bank run scenarios

**Output:** Detailed metrics in `results/` directory.

### Tier 3: Full Ecosystem (30+ minutes)

Comprehensive long-running simulations with multi-actor dynamics and report generation.

```bash
# Run full ecosystem simulation
pnpm run sim:run

# Generate simulation report
pnpm exec tsx scripts/generate-simulation-report.ts ./simulation-results/full-ecosystem/metrics.json ./simulation-results/full-ecosystem/reports
```

**What it tests:**
- Multi-day ecosystem dynamics
- Revenue projections at various FDV levels
- User growth and retention patterns
- Cross-feature adoption metrics

**Output:** JSON and Markdown reports in `simulation-results/reports/`.

## Available Scripts

### Smoke Tests

| Script | Description |
|--------|-------------|
| `smoke:all` | Core smoke test suite |
| `smoke:extended` | Extended smoke tests including staking |
| `smoke:edge-cases` | Edge case validation |
| `smoke:agents` | Individual agent behavior tests |

### Integration Tests

| Script | Description |
|--------|-------------|
| `integration:full` | Full protocol flow |
| `integration:staking` | Staking stress test |
| `integration:rewards` | Reward distribution |

### Economic Scenarios

| Script | Description |
|--------|-------------|
| `economic:bank-run` | Liquidity crisis simulation |
| `economic:whale` | Whale accumulation dynamics |
| `economic:fee-timing` | Fee epoch timing edge cases |
| `economic:governance-attack` | Governance manipulation |
| `economic:long-running` | Extended projections |

### Stress Tests

| Script | Description |
|--------|-------------|
| `stress:high-freq` | High-frequency trading |
| `stress:small-txs` | Many small transactions |
| `stress:liquidity` | Liquidity crisis |
| `stress:gov-spam` | Governance spam |
| `stress:flash` | Flash attack scenarios |

## Output Directories

After running simulations, outputs are stored in:

```
sim/
├── results/              # Smoke and integration test results
│   ├── smoke-*.json
│   └── integration-*.json
├── simulation-results/   # Full simulation outputs
│   ├── metrics.json      # Raw metrics
│   └── reports/          # Generated reports
│       ├── simulation-report.json
│       └── simulation-report.md
```

## CI Integration

Simulations run automatically via GitHub Actions:

- **On PR/Push**: Smoke tests run on changes to `sim/**`, `src/**`, or `script/**`
- **On Main**: Full ecosystem simulation with artifact upload

Artifacts are available for download from the Actions tab. See [.github/workflows/simulation-ci.yml](../.github/workflows/simulation-ci.yml).

## Metrics Collected

The simulation framework tracks:

| Metric Category | Examples |
|-----------------|----------|
| **Token Metrics** | Total supply, veELTA locked, staking rate |
| **App Metrics** | Apps created, graduation rate, trading volume |
| **Fee Metrics** | Fees collected, distributed, treasury revenue |
| **User Metrics** | Unique users, DAU, revenue per user |
| **Feature Adoption** | Trades, staking events, governance votes |

## Adding New Scenarios

1. Create a new file in `scenarios/` following existing patterns
2. Import `EltaPack` from `packs/`
3. Define agents and their behaviors
4. Run simulation and collect metrics
5. Add to appropriate npm script in `package.json`

See [docs/SCENARIOS.md](./docs/SCENARIOS.md) for detailed guidance.

## Development

```bash
# Build TypeScript
pnpm run build

# Watch mode
pnpm run build:watch

# Type check
pnpm run typecheck

# Lint
pnpm run lint:fix
```

## Requirements

- Node.js 20+
- pnpm
- Foundry (forge, anvil)
- Protocol contracts built (`cd .. && make build`)
