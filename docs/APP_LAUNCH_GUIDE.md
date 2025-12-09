# App Launch Guide

This guide walks through creating an app on the Elata Protocol, from initial token launch to deploying utility modules.

## Overview

Launching an app involves:

1. Creating an app token via AppFactory
2. Deploying utility modules (staking, items, rewards)
3. Configuring your app's economy
4. Building your frontend to interact with the contracts

By the end, you'll have a fully functional token economy for your neurotech application.

## Prerequisites

Before starting:

- Local environment running (`npm run local:up` in elata-protocol)
- ELTA tokens for the launch fee (110 ELTA minimum)
- Basic Solidity knowledge for understanding contract interactions

## Step 1: Create Your App Token

### Using the Factory

The AppFactory creates your token and bonding curve in a single transaction. You'll need 110 ELTA: 100 for seed liquidity and 10 as a creation fee.

```solidity
// First, approve ELTA spending
ELTA.approve(address(appFactory), 110 ether);

// Create the app
uint256 appId = appFactory.createApp(
    "NeuroPong Token",    // Token name
    "NPONG",              // Token symbol  
    0,                    // Supply (0 = default 1 billion)
    "EEG-controlled pong game",  // Description
    "ipfs://Qm...",       // Image URI
    "https://neuropong.app"      // Website
);
```

### What Gets Deployed

The factory deploys three contracts:

1. **AppToken** — Your ERC20 token with 1 billion supply
2. **AppBondingCurve** — Handles trading before graduation
3. **AppStakingVault** — For staking your token

### Token Distribution

After creation:

- 50% (500M tokens) go to you, auto-staked in the vault
- 50% (500M tokens) go to the bonding curve for public trading

Your tokens are staked automatically, so you start earning rewards immediately. To access them, you'll need to unstake first.

### Retrieve Your Addresses

```solidity
// Get your app's data
AppFactory.App memory app = appFactory.apps(appId);

address token = app.token;
address bondingCurve = app.bondingCurve;
address stakingVault = app.vault;
```

## Step 2: Deploy Utility Modules

The AppModuleFactory adds utility modules to your app. This deploys additional contracts you'll use for items, rewards, and more.

```solidity
// Deploy modules
(address access1155, address staking, address rewards) = 
    appModuleFactory.deployModules(
        token,                              // Your app token address
        "https://api.myapp.com/metadata/"   // Base URI for NFT metadata
    );
```

### Modules Deployed

| Contract | Purpose |
|----------|---------|
| AppAccess1155 | ERC1155 for in-app items and passes |
| AppStakingVault | Additional staking vault (if needed) |
| EpochRewards | Time-boxed reward distribution |

You own all these contracts after deployment.

## Step 3: Configure Items

The AppAccess1155 contract lets you create purchasable items. Users burn your token to buy items.

### Create an Item

```solidity
AppAccess1155 access = AppAccess1155(access1155);

access.setItem(
    1,              // Item ID
    50 ether,       // Price in app tokens (50 tokens)
    true,           // Soulbound (non-transferable)
    true,           // Active (can be purchased)
    0,              // Start time (0 = no restriction)
    0,              // End time (0 = no restriction)
    10000,          // Max supply (0 = unlimited)
    "ipfs://Qm..."  // Metadata URI
);
```

### Item Parameters

| Parameter | Description |
|-----------|-------------|
| `itemId` | Unique identifier for this item |
| `price` | Cost in app tokens (burned on purchase) |
| `soulbound` | If true, item can't be transferred |
| `active` | If false, purchases are disabled |
| `startTime` | Unix timestamp when sales start |
| `endTime` | Unix timestamp when sales end |
| `maxSupply` | Maximum items that can exist |
| `uri` | Metadata URI for the item |

### Create Multiple Tiers

```solidity
// Basic pass - cheap, unlimited
access.setItem(1, 10 ether, true, true, 0, 0, 0, "ipfs://basic");

// Premium pass - mid-tier
access.setItem(2, 100 ether, true, true, 0, 0, 1000, "ipfs://premium");

// Legendary pass - expensive, rare
access.setItem(3, 1000 ether, true, true, 0, 0, 100, "ipfs://legendary");
```

## Step 4: Configure Feature Gates

Feature gates let you restrict app features based on staking or item ownership.

### Stake-Based Gate

Require users to stake tokens to access a feature:

```solidity
access.setFeatureGate(
    keccak256("premium_mode"),  // Feature identifier
    FeatureGate({
        minStake: 1000 ether,   // Require 1000 tokens staked
        requiredItem: 0,         // No item required
        requireBoth: false,
        active: true
    })
);
```

### Item-Based Gate

Require users to own an item:

```solidity
access.setFeatureGate(
    keccak256("vip_room"),
    FeatureGate({
        minStake: 0,
        requiredItem: 3,         // Require legendary pass (ID 3)
        requireBoth: false,
        active: true
    })
);
```

### Combined Gate

Require both staking and item ownership:

```solidity
access.setFeatureGate(
    keccak256("exclusive_tournament"),
    FeatureGate({
        minStake: 5000 ether,    // 5000 tokens staked
        requiredItem: 2,          // AND premium pass
        requireBoth: true,        // Both required
        active: true
    })
);
```

### Check Access in Your App

Your frontend or backend checks access before enabling features:

```solidity
bool hasAccess = access.checkFeatureAccess(
    userAddress,
    keccak256("premium_mode"),
    stakingVault.balanceOf(userAddress)  // User's stake
);
```

## Step 5: Run Tournaments

The TournamentFactory creates individual tournament contracts for competitive events.

### Create a Tournament

```solidity
Tournament tournament = TournamentFactory(tournamentFactory).createTournament(
    token,                          // Prize token
    100 ether,                      // Entry fee per player
    block.timestamp,                // Registration starts now
    block.timestamp + 7 days,       // Registration ends in 7 days
    block.timestamp + 8 days        // Tournament ends in 8 days
);
```

### Tournament Lifecycle

1. **Registration** — Users pay entry fee to join
2. **Running** — Your app determines rankings off-chain
3. **Finalization** — You submit results as a Merkle root
4. **Claims** — Winners claim prizes with proofs

### Finalize and Distribute

After the tournament:

```solidity
// Generate Merkle tree from results off-chain
bytes32 merkleRoot = computeMerkleRoot(results);

// Finalize on-chain
tournament.finalize(merkleRoot);

// Winners claim their share
tournament.claim(winnerAddress, amount, merkleProof);
```

### Fee Structure

| Fee | Amount | Destination |
|-----|--------|-------------|
| Protocol fee | 2.5% | Treasury |
| Burn fee | 1% | Burned |
| Prize pool | 96.5% | Winners |

## Step 6: Distribute Rewards

The EpochRewards contract handles time-boxed reward distributions.

### Create an Epoch

```solidity
EpochRewards rewards = EpochRewards(rewardsAddress);

// Start a new epoch
uint256 epochId = rewards.createEpoch(
    block.timestamp,           // Start time
    block.timestamp + 7 days   // End time
);

// Fund the epoch from your treasury
token.approve(address(rewards), 100000 ether);
rewards.fund(epochId, 100000 ether);
```

### Finalize with Merkle Root

After computing rewards off-chain:

```solidity
// Generate Merkle tree from reward allocations
bytes32 merkleRoot = computeMerkleRoot(allocations);

// Finalize the epoch
rewards.finalizeEpoch(epochId, merkleRoot);
```

### User Claims

Users claim their rewards:

```solidity
rewards.claim(epochId, userAddress, amount, merkleProof);
```

## Complete Example

Here's a full launch script:

```solidity
// 1. Approve and create app
ELTA.approve(address(appFactory), 110 ether);
uint256 appId = appFactory.createApp(
    "BrainFlow",
    "FLOW",
    0,
    "Meditation with EEG feedback",
    "ipfs://...",
    "https://brainflow.app"
);

AppFactory.App memory app = appFactory.apps(appId);

// 2. Deploy modules
(address access, , address rewards) = appModuleFactory.deployModules(
    app.token,
    "https://api.brainflow.app/items/"
);

// 3. Configure items
AppAccess1155(access).setItem(
    1, 25 ether, true, true, 0, 0, 0, "ipfs://basic-meditation"
);
AppAccess1155(access).setItem(
    2, 100 ether, true, true, 0, 0, 500, "ipfs://guided-meditation"
);

// 4. Set up feature gate
AppAccess1155(access).setFeatureGate(
    keccak256("advanced_sessions"),
    FeatureGate({
        minStake: 500 ether,
        requiredItem: 0,
        requireBoth: false,
        active: true
    })
);

// Ready for users!
```

## Frontend Integration

Your app interacts with these contracts via standard Ethereum libraries.

### Read Token Balance

```typescript
import { useReadContract } from 'wagmi';

const { data: balance } = useReadContract({
  address: tokenAddress,
  abi: AppTokenABI,
  functionName: 'balanceOf',
  args: [userAddress],
});
```

### Buy on Bonding Curve

```typescript
import { useWriteContract } from 'wagmi';

const { writeContract } = useWriteContract();

// First approve ELTA
await writeContract({
  address: eltaAddress,
  abi: ELTAABI,
  functionName: 'approve',
  args: [bondingCurveAddress, amount],
});

// Then buy
await writeContract({
  address: bondingCurveAddress,
  abi: BondingCurveABI,
  functionName: 'buy',
  args: [amount, minTokensOut],
});
```

### Check Feature Access

```typescript
const { data: hasAccess } = useReadContract({
  address: accessAddress,
  abi: AppAccess1155ABI,
  functionName: 'checkFeatureAccess',
  args: [userAddress, featureId, userStake],
});
```

## Best Practices

### Token Economics

- Start with conservative pricing—you can lower prices later
- Use soulbound items for access passes to prevent resale markets
- Keep some tokens in reserve for future rewards and marketing

### Feature Gates

- Don't gate too aggressively early on—let users try your app
- Use staking gates to encourage long-term engagement
- Use item gates for premium content

### Tournaments

- Start with small prize pools to test the flow
- Make entry fees proportional to expected skill level
- Communicate rules clearly before registration opens

### Security

- Test thoroughly on local and testnet before mainnet
- Consider time-limited items for seasonal content
- Monitor your contracts after launch

## Troubleshooting

### "Insufficient ELTA" on app creation

You need 110 ELTA and gas. Get test ELTA:

```bash
npm run faucet <your-address>
```

### Can't deploy modules

Only the token owner can deploy modules. Make sure you're calling from the address that created the app.

### Items not appearing

Check that:
- Item is set to `active: true`
- Current time is within start/end window
- Max supply hasn't been reached

### Users can't buy on curve

During the first 6 hours, only users with 100+ XP can buy. This is the early access period.

## Contract References

| Contract | Source |
|----------|--------|
| AppFactory | [src/apps/AppFactory.sol](../src/apps/AppFactory.sol) |
| AppToken | [src/apps/AppToken.sol](../src/apps/AppToken.sol) |
| AppBondingCurve | [src/apps/AppBondingCurve.sol](../src/apps/AppBondingCurve.sol) |
| AppModuleFactory | [src/apps/AppModuleFactory.sol](../src/apps/AppModuleFactory.sol) |
| AppAccess1155 | [src/apps/AppAccess1155.sol](../src/apps/AppAccess1155.sol) |
| AppStakingVault | [src/apps/AppStakingVault.sol](../src/apps/AppStakingVault.sol) |
| Tournament | [src/apps/Tournament.sol](../src/apps/Tournament.sol) |
| TournamentFactory | [src/apps/TournamentFactory.sol](../src/apps/TournamentFactory.sol) |

## Next Steps

- [TOKENOMICS.md](./TOKENOMICS.md) — Understanding the broader economic design
- [ARCHITECTURE.md](./ARCHITECTURE.md) — How all contracts fit together
- [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md) — Testing your integration locally

