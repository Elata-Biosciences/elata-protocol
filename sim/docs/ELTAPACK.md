# EltaPack API Reference

This document describes the EltaPack class, which implements the AgentForge Pack interface for the Elata Protocol.

## Overview

EltaPack handles:
- Contract deployment to Anvil
- Action execution against real contracts
- World state management
- Metrics collection
- Agent wallet management

## Configuration

```typescript
import { createEltaPack } from './packs/EltaPack.js';

const pack = createEltaPack({
  protocolPath: '/path/to/elata-protocol',
  anvilPort: 8545,
  initialEltaSupply: BigInt(10000000e18),
  agentEthBalance: BigInt(1000e18),
  agentEltaBalance: BigInt(10000e18),
  autoDeploy: true,
  silent: true,
  deployScript: 'script/Deploy.sol:Deploy',
  deployScriptArgs: ['--code-size-limit', '50000', '--skip-simulation'],
});
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `protocolPath` | `string` | *required* | Path to elata-protocol Foundry project |
| `anvilPort` | `number` | 8545 | Port for Anvil instance |
| `initialEltaSupply` | `bigint` | 10M ELTA | Initial ELTA token supply |
| `agentEthBalance` | `bigint` | 1000 ETH | ETH balance per agent |
| `agentEltaBalance` | `bigint` | 10000 ELTA | ELTA balance per agent |
| `autoDeploy` | `boolean` | true | Auto-deploy contracts on init |
| `silent` | `boolean` | false | Suppress Anvil output |
| `deployScript` | `string` | 'script/Deploy.sol:Deploy' | Deployment script path |
| `deployScriptArgs` | `string[]` | [...] | Extra forge script args |
| `funding` | `FundingConfig` | undefined | Custom agent funding config |

## World State

```typescript
interface EltaWorldState extends WorldState {
  // Contract addresses
  elta: Address;
  veElta: Address;
  appFactory: Address;
  feeRouter: Address;
  rewardsDistributor: Address;
  elataPoints: Address;

  // Protocol state
  totalEltaSupply: bigint;
  totalVeEltaLocked: bigint;
  appCount: number;

  // Apps
  apps: Map<string, AppState>;

  // Fee tracking
  feesCollectedTotal: bigint;
  feesDistributed: bigint;

  // Block info
  blockNumber: bigint;
  timestamp: number;
}

interface AppState {
  id: number;
  name: string;
  symbol: string;
  creator: Address;
  tokenAddress: Address;
  curveAddress: Address;
  graduated: boolean;
  totalRaised: bigint;
  tokenPrice: bigint;
  tokenSupply: bigint;
}
```

## Core Methods

### Lifecycle

```typescript
// Initialize pack (starts Anvil, deploys contracts)
await pack.initialize(ctx);

// Called at start of each tick
pack.onTick(tick, timestamp);

// Cleanup (stops Anvil)
await pack.cleanup();
```

### Agent Management

```typescript
// Register agent and get wallet address
const address = await pack.registerAgent(agentId);

// Fund agent with ELTA
await pack.fundAgentWithELTA(address, amount);

// Grant XP to agent
await pack.grantAgentXP(address);
```

### State Access

```typescript
// Get world state
const state = pack.getWorldState();

// Get metrics
const metrics = pack.getMetrics();

// Get deployed contract addresses
const addresses = pack.getContractAddresses();
```

## Action Execution

```typescript
const result = await pack.executeAction(action, agentId);

if (result.ok) {
  console.log(`Gas used: ${result.gasUsed}`);
} else {
  console.log(`Error: ${result.error}`);
}
```

### Supported Actions

#### Trading Actions

| Action | Description |
|--------|-------------|
| `buy_app_token` | Buy app tokens from bonding curve |
| `sell_app_token` | Sell app tokens (post-graduation only) |
| `create_app` | Create new app via AppFactory |

#### veELTA Actions

| Action | Description |
|--------|-------------|
| `lock_veelta` | Lock ELTA for veELTA |
| `unlock_veelta` | Unlock expired veELTA |
| `extend_lock` | Extend lock duration |
| `increase_amount` | Add more ELTA to lock |

#### Staking Actions

| Action | Description |
|--------|-------------|
| `stake_app_token` | Stake app tokens in vault |
| `unstake_app_token` | Unstake app tokens |
| `claim_rewards` | Claim veELTA rewards |
| `claim_app_rewards` | Claim app staking rewards |

#### Tournament Actions

| Action | Description |
|--------|-------------|
| `create_tournament` | Create new tournament |
| `enter_tournament` | Enter tournament |
| `claim_tournament_prize` | Claim prize |
| `finalize_tournament` | Finalize tournament |

#### Content Actions

| Action | Description |
|--------|-------------|
| `list_content` | List content for sale |
| `purchase_content` | Purchase content NFT |
| `list_content_with_time_window` | List with time constraints |
| `deactivate_content` | Deactivate listing |
| `reactivate_content` | Reactivate listing |

#### Governance Actions

| Action | Description |
|--------|-------------|
| `create_proposal` | Create governance proposal |
| `cast_vote` | Vote on proposal |
| `queue_proposal` | Queue passed proposal |
| `execute_proposal` | Execute queued proposal |

#### Fee Actions

| Action | Description |
|--------|-------------|
| `sweep_fees` | Sweep fees from curves |
| `close_fee_epoch` | Close current fee epoch |

#### Other Actions

| Action | Description |
|--------|-------------|
| `set_referrer` | Set referrer address |
| `claim_referral_rewards` | Claim referral rewards |
| `claim_airdrop` | Claim airdrop |
| `claim_xp_points` | Claim XP points |
| `release_vested_tokens` | Release vested tokens |

## Helper Methods for Agents

### Balance Queries

```typescript
// Get ELTA balance
const elta = await pack.getAgentEltaBalance(agentId);

// Get veELTA balance
const veElta = await pack.getAgentVeEltaBalance(agentId);

// Get app token balance
const appTokens = await pack.getAgentAppTokenBalance(agentId, appId);
```

### State Queries

```typescript
// Get claimable rewards info
const rewards = await pack.getClaimableRewardsEpochs(agentId);
// { hasClaimableRewards: boolean, lastClaimed: bigint, totalEpochs: bigint }

// Get staked balance
const staked = await pack.getAgentStakedBalance(agentId, appId);

// Get proposal state (0=Pending, 1=Active, ..., 7=Executed)
const state = await pack.getProposalState(proposalId);

// Check if agent has voted
const voted = await pack.hasVotedOnProposal(agentId, proposalId);

// Get app claimable epochs
const appRewards = await pack.getAppClaimableEpochs(agentId, appId);
```

### Utility Methods

```typescript
// Take state snapshot
const snapshotId = await pack.snapshot();

// Revert to snapshot
await pack.revert(snapshotId);

// Get Anvil URL
const url = pack.getAnvilUrl();

// Get public client
const client = pack.getPublicClient();
```

## Metrics Tracking

### Base Metrics

- `elta_total_supply`: Total ELTA supply
- `veelta_total_locked`: Total veELTA locked
- `app_count`: Number of apps
- `graduated_apps`: Graduated app count
- `fees_collected_total`: Total fees collected
- `fees_distributed`: Fees distributed
- `gas_total`: Total gas used

### Per-App Metrics

- `app_{id}_price`: Current token price
- `app_{id}_raised`: Amount raised
- `app_{id}_graduated`: Graduation status
- `app_{id}_price_change_bps`: Price change in basis points

### Gas Metrics

- `gas_per_agent_{id}`: Gas used by agent
- `gas_per_action_{type}`: Gas used by action type

### P&L Metrics

- `agent_{id}_realized_pnl`: Agent's realized P&L

## Internal State

The pack maintains several internal tracking structures:

```typescript
// Price history (appId -> tick -> price)
private priceHistory: Map<string, Map<number, bigint>>

// Starting balances for P&L calculation
private agentStartingBalances: Map<string, bigint>

// Realized P&L tracking
private agentRealizedPnL: Map<string, bigint>

// Gas usage aggregation
private gasUsedByAgent: Map<string, bigint>
private gasUsedByAction: Map<string, bigint>
private totalGasUsed: bigint

// Lock state cache
private lockStateCache: Map<Address, { hasLock: boolean; unlockTime: bigint }>
```

## Event Parsing

The pack automatically parses events from transaction receipts:

- `AppCreated`: New app creation
- `AppGraduated`: App graduation (bonding curve completion)

## Error Handling

Action results include error information:

```typescript
interface ActionResult {
  ok: boolean;
  error?: string;
  gasUsed?: bigint;
}
```

Common errors:
- Contract not deployed
- Insufficient balance
- Lock exists/expired
- Not authorized
- Reverts from contract logic

## Example Usage

```typescript
import { createEltaPack } from './packs/EltaPack.js';

const pack = createEltaPack({
  protocolPath: './elata-protocol',
  anvilPort: 8545,
});

// In simulation engine
await pack.initialize(ctx);

// Register agent
const address = await pack.registerAgent('agent-1');

// Execute action
const result = await pack.executeAction(
  {
    id: 'buy-1',
    name: 'buy_app_token',
    params: {
      type: 'buy_app_token',
      appId: '1',
      appAddress: '0x...',
      eltaAmount: BigInt(100e18),
    },
  },
  'agent-1'
);

// Get metrics
const metrics = pack.getMetrics();
console.log(`Total gas: ${metrics.gas_total}`);

// Cleanup
await pack.cleanup();
```
