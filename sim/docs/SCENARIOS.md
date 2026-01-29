# Scenario Creation Guide

This document explains how to create and run simulation scenarios for the Elata Protocol.

## Overview

Scenarios define the simulation parameters: agents, duration, metrics, and assertions. They use the `defineScenario` API from AgentForge.

## Basic Structure

```typescript
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from 'agentforge';
import { BasicUserAgent, DeveloperAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8545,
  silent: true,
});

const scenario = defineScenario({
  name: 'my-scenario',
  seed: 42,
  ticks: 30,
  tickSeconds: 3600,
  pack,
  agents: [...],
  metrics: {...},
  assertions: [...],
});

export { scenario };
```

## Configuration Options

### Core Settings

| Option | Type | Description |
|--------|------|-------------|
| `name` | `string` | Unique scenario identifier |
| `seed` | `number` | RNG seed for reproducibility |
| `ticks` | `number` | Number of simulation ticks |
| `tickSeconds` | `number` | Simulated seconds per tick |
| `pack` | `Pack` | Protocol pack instance |

### Agent Configuration

```typescript
agents: [
  {
    type: BasicUserAgent,  // Agent class
    count: 10,             // Number of instances
    params: {              // Agent-specific parameters
      buyProbability: 0.3,
      sellProbability: 0.2,
    },
  },
]
```

### Metrics Configuration

```typescript
metrics: {
  sampleEveryTicks: 5,  // Sample interval
  track: [
    'app_count',
    'veelta_total_locked',
    'fees_collected_total',
    'gas_total',
  ],
}
```

### Available Metrics

| Metric | Description |
|--------|-------------|
| `elta_total_supply` | Total ELTA token supply |
| `veelta_total_locked` | Total veELTA locked |
| `app_count` | Number of apps created |
| `graduated_apps` | Number of graduated apps |
| `fees_collected_total` | Total fees collected |
| `fees_distributed` | Total fees distributed |
| `gas_total` | Total gas used |
| `app_{id}_price` | Price of app token |
| `app_{id}_raised` | Amount raised for app |
| `app_{id}_graduated` | Graduation status (0/1) |
| `app_{id}_price_change_bps` | Price change in basis points |
| `gas_per_agent_{id}` | Gas used by agent |
| `gas_per_action_{type}` | Gas used by action type |
| `agent_{id}_realized_pnl` | Agent realized P&L |

### Assertions

```typescript
assertions: [
  { type: 'gte', metric: 'app_count', value: 3 },
  { type: 'lte', metric: 'graduated_apps', value: 10 },
  { type: 'eq', metric: 'some_metric', value: expectedValue },
]
```

Assertion Types:
- `gte`: Greater than or equal
- `lte`: Less than or equal
- `gt`: Greater than
- `lt`: Less than
- `eq`: Equal

## Running Scenarios

### Programmatic Execution

```typescript
async function main(): Promise<void> {
  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  const result = await engine.run(scenario, {
    outDir: './results/my-scenario',
    ci: true,
  });

  console.log(`Result: ${result.success ? 'PASS' : 'FAIL'}`);
  console.log(`Duration: ${result.durationMs}ms`);
  
  // Access final metrics
  console.log(result.finalMetrics);
  
  // Access agent stats
  for (const stat of result.agentStats) {
    console.log(`${stat.id}: ${stat.actionsSucceeded}/${stat.actionsAttempted}`);
  }

  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}
```

### NPM Scripts

Add to `package.json`:

```json
{
  "scripts": {
    "scenario:my-scenario": "tsx scenarios/my-scenario.ts"
  }
}
```

## Scenario Types

### Smoke Tests

Quick validation tests (< 20 ticks):

```typescript
// scenarios/smoke/my-smoke-test.ts
const scenario = defineScenario({
  name: 'smoke-my-feature',
  seed: 42,
  ticks: 15,
  tickSeconds: 3600,
  // ...
});
```

### Integration Tests

Full flow tests (20-50 ticks):

```typescript
// scenarios/integration/full-flow.ts
const scenario = defineScenario({
  name: 'integration-full-flow',
  seed: 100,
  ticks: 50,
  tickSeconds: 1800,
  // ...
});
```

### Economic Scenarios

Economic behavior tests (30-100 ticks):

```typescript
// scenarios/economic/bank-run.ts
const scenario = defineScenario({
  name: 'economic-bank-run',
  seed: 123,
  ticks: 60,
  tickSeconds: 1800,
  // ...
});
```

## Pack Configuration

### EltaPack Options

```typescript
const pack = createEltaPack({
  // Required
  protocolPath: '/path/to/elata-protocol',
  
  // Optional
  anvilPort: 8545,                    // Anvil RPC port
  initialEltaSupply: BigInt(10000000e18),  // Initial ELTA supply
  agentEthBalance: BigInt(1000e18),   // ETH per agent
  agentEltaBalance: BigInt(10000e18), // ELTA per agent
  autoDeploy: true,                   // Auto-deploy contracts
  silent: true,                       // Quiet Anvil output
  deployScript: 'script/Deploy.sol:Deploy',  // Deployment script
});
```

## Best Practices

### 1. Use Meaningful Seeds

```typescript
// Use different seeds for different test purposes
const scenario = defineScenario({
  seed: 42,     // Deterministic base
  seed: Date.now(), // Random variation
});
```

### 2. Scale Agent Counts

```typescript
// Match agent counts to tick count
agents: [
  { type: DeveloperAgent, count: Math.ceil(ticks / 20) },
  { type: BasicUserAgent, count: Math.ceil(ticks / 3) },
]
```

### 3. Balance Risk Parameters

```typescript
// Mix risk tolerances for realistic behavior
agents: [
  { type: BasicUserAgent, count: 5, params: { riskTolerance: 0.3 } },
  { type: BasicUserAgent, count: 3, params: { riskTolerance: 0.6 } },
  { type: BasicUserAgent, count: 2, params: { riskTolerance: 0.9 } },
]
```

### 4. Use Unique Anvil Ports

```typescript
// Avoid port conflicts between parallel tests
const pack = createEltaPack({
  anvilPort: 8545 + scenarioIndex,
  // ...
});
```

### 5. Output Analysis

```typescript
// Log useful information
console.log('\nPrice Analysis:');
for (const [key, value] of Object.entries(result.finalMetrics)) {
  if (key.includes('_price')) {
    console.log(`  ${key}: ${value}`);
  }
}
```

## Example Scenarios

### Healthy Growth

Tests normal protocol operation:
- Developers create apps
- Users trade
- Stakers lock veELTA
- Rewards are claimed

### Whale Dominance

Tests concentration effects:
- Few large traders
- High-volume trading
- Impact on prices

### Attack Resistance

Tests adversarial behavior:
- Manipulator agents
- Spammer agents
- System stability

### Bank Run

Tests panic scenarios:
- Mass selling
- Price floor behavior
- Liquidity depth

See `scenarios/` directory for complete examples.
