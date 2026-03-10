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
# Install dependencies (pulls @elata-biosciences/agentforge from npm)
pnpm install

# Run smoke tests (validates basic functionality)
pnpm run smoke:all
```

## Three-Tier Simulation Guide

Choose the appropriate tier based on your time and validation needs:

### Protocol Lanes (recommended)

```bash
# PR/quick lane: critical protocol coverage
pnpm run protocol:fast
pnpm run results:validate:fast

# Balanced lane: broad adversarial/economic/growth/resilience coverage
pnpm run protocol:balanced
pnpm run results:validate:balanced

# Deep lane: extended smoke + integration + economic + stress
pnpm run protocol:deep
pnpm run results:validate:deep
```

The validation scripts read the latest `results/**/summary.json` and fail if required scenarios are missing or failed.

### Viewing Runs (Studio + Dashboard)

```bash
# Launch AgentForge Studio on a free port and scan ./results
pnpm run studio

# Same as above, but auto-open browser
pnpm run studio:open

# Generate/open static HTML dashboard from all results
pnpm run dashboard:open
```

If you need a fixed local port for bookmarks or scripts:

```bash
pnpm run studio:8790
```

### LLM + Gossip Scenarios

Real-provider LLM scenarios are under `scenarios/llm/` and include gossip coordination so message
history is visible in Studio.

```bash
# Required for provider-backed exploration runs (OpenAI default)
export OPENAI_API_KEY="..."
export OPENAI_MODEL="gpt-4o-mini"

# Optional provider override (default is openai)
export LLM_GOSSIP_PROVIDER="openai"

# Optional: OpenRouter (only needed if you switch provider)
# export LLM_GOSSIP_PROVIDER="openrouter"
# export OPENROUTER_API_KEY="..."
# export OPENROUTER_MODEL="openai/gpt-4o-mini"

# Run non-deterministic provider-backed gossip scenarios
pnpm run llm:governance-gossip
pnpm run llm:adversarial-rumor
pnpm run llm:persona-matrix

# Or run all
pnpm run llm:all

# Deterministic lane (same scenarios, no live provider calls)
pnpm run llm:governance-gossip:deterministic
pnpm run llm:adversarial-rumor:deterministic
pnpm run llm:persona-matrix:deterministic
```

Mode semantics (Studio Start Run):

- `Deterministic baseline`: reproducible by seed; no live LLM calls in coordinator agents.
- `Non-deterministic exploration`: live provider-generated gossip content.
- `Replay`: deterministic re-run from a captured exploration bundle.

For direct `tsx` scripts above, provider mode is toggled via `LLM_GOSSIP_FORCE_PROVIDER=1`.
By default, both LLM gossip scenarios now use `OPENAI_API_KEY` + `OPENAI_MODEL` from environment.

#### LLM reliability controls

Provider clients now include retry + timeout behavior for transient API/network failures:

```bash
export AGENTFORGE_LLM_TIMEOUT_MS=20000
export AGENTFORGE_LLM_MAX_ATTEMPTS=3
export AGENTFORGE_LLM_RETRY_BASE_MS=300
export AGENTFORGE_LLM_RETRY_MAX_MS=2500
```

Deterministic consistency smoke lane:

```bash
pnpm run llm:smoke
```

This runs deterministic LLM scenarios, validates gossip/persona artifacts, and performs a repeat-run
consistency check for governance-gossip outputs.

### Persona LLM extension pattern

Persona agents are layered:
- AgentForge generic base: `PersonaLlmAgentBase`
- Elata protocol base: `BaseElataPersonaLlmAgent`
- concrete personas: creator, economic, bad actor, saboteur, hacker

Persona runs now use:
- capability manifest context (`ctx.capabilities`) with contracts, query endpoints, and tool templates
- two-stage LLM flow (`plan` then `action`) with fallback to legacy single-shot parsing
- per-tick observation deltas + compact memory summaries to reduce prompt bloat

To add a persona, create a thin subclass that defines:
- `getPersonaProfile()` (style, goals, risk)
- `getAllowedProtocolActions()`
- `getFallbackIntent(ctx)` for deterministic fallback behavior

### Autonomous RPC controls (exploration mode)

Use aggressive autonomy for persona exploration runs:

```bash
export AGENTFORGE_AUTONOMOUS_RPC_POLICY=aggressive
```

Emergency kill-switch:

```bash
export AGENTFORGE_DISABLE_AUTONOMOUS_RPC=1
```

These can also be set per-scenario via `exploration.autonomousRpcPolicy` and `exploration.disableAutonomousRpc`.

### Persona usefulness artifact

Run post-analysis to generate persona usefulness scoring artifacts (`persona_quality.json`) from
action traces:

```bash
pnpm run analyze
```

Validate minimum usefulness threshold in CI:

```bash
pnpm run results:validate:persona
```

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

### Expanded Scenario Families

| Script | Description |
|--------|-------------|
| `adversarial:all` | Strategy arms race + governance pressure |
| `economic:new-all` | Fee cadence + rebalancing/liquidity economics |
| `growth:all` | Bursty launches + retention mix |
| `resilience:all` | Congestion recovery + liquidity shock absorption |
| `llm:all` | LLM-driven gossip coordination scenarios |

### Agent Calibration

```bash
# Deterministic reproducibility + stochastic variation checks
pnpm run agents:calibrate
```

This script verifies that deterministic policy agents are reproducible under fixed seeds while stochastic agents show healthy variation across multiple seeds.

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

- **Fast lane (PR/Push)**: protocol critical path suite + summary validation
- **Deep lane (Main/Manual)**: extended protocol suite + summary validation
- **Full ecosystem (Main/Manual)**: long-run simulation with report artifacts

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

### Notebook-style Studio Markdown

Each scenario can embed user-facing markdown explanations through `studio.report`:

- `Experiment Notes`: what the run is testing and why
- `Results Commentary`: interpretation and caveats
- `How to Read This`: guidance for dashboard viewers

Use `sim/lib/studio-report.ts` (`createNotebookReport`) to keep report structure consistent while customizing per-scenario markdown text.

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
