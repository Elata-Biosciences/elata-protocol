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
(address content721, address contentStore) = 
    appModuleFactory.deployModules(
        appId,                                // Your app ID
        appToken,                             // Your app token address
        "My Content",                         // Collection name
        "CONTENT",                            // Collection symbol
        "https://api.myapp.com/contract"      // Contract metadata URI
    );
```

### Modules Deployed

| Contract | Purpose |
|----------|---------|
| InAppContent721 | ERC-721 for digital content and collectibles |
| ContentStore | Primary sales with time windows and feature gates |
| AppStakingVault | Token staking (deployed by AppFactory) |

You own all these contracts after deployment.

## Step 3: List Content

The ContentStore contract lets you list purchasable content. Users pay with app tokens and receive an ERC-721 token.

### List Content

```solidity
ContentStore store = ContentStore(contentStore);

uint256 contentId = store.listContent(
    "ipfs://Qm...",     // Metadata URI
    50 ether,           // Price in app tokens (50 tokens)
    10000,              // Max supply (0 = unlimited)
    PaymentTokenType.APP // Payment in app token
);
```

### Content Parameters

| Parameter | Description |
|-----------|-------------|
| `uri` | Metadata URI for the content |
| `price` | Cost in payment tokens |
| `maxSupply` | Maximum items that can be minted (0 = unlimited) |
| `paymentType` | APP, ELTA, or USDC |

### List with Time Windows

```solidity
// Limited-time sale
store.listContentWithTimeWindow(
    "ipfs://limited",
    100 ether,
    1000,
    PaymentTokenType.APP,
    uint64(block.timestamp + 1 days),  // Start time
    uint64(block.timestamp + 7 days)   // End time
);
```

### Create Multiple Tiers

```solidity
// Basic content - cheap, unlimited
store.listContent("ipfs://basic", 10 ether, 0, PaymentTokenType.APP);

// Premium content - mid-tier
store.listContent("ipfs://premium", 100 ether, 1000, PaymentTokenType.APP);

// Legendary content - expensive, rare
store.listContent("ipfs://legendary", 1000 ether, 100, PaymentTokenType.APP);
```

## Step 4: Configure Feature Gates

Feature gates let you restrict app features based on staking or content ownership.

### Stake-Based Gate

Require users to stake tokens to access a feature:

```solidity
store.setFeatureGate(
    keccak256("premium_mode"),  // Feature identifier
    1000 ether,                 // minStake: Require 1000 tokens staked
    0,                          // requiredContentId: No content required
    false,                      // requireBoth: false
    true                        // active: true
);
```

### Content-Based Gate

Require users to have purchased specific content:

```solidity
store.setFeatureGate(
    keccak256("vip_room"),
    0,                          // minStake: No stake required
    2,                          // requiredContentId: Require content ID 2
    false,                      // requireBoth: false
    true                        // active: true
);
```

### Combined Gate

Require both staking and content ownership:

```solidity
store.setFeatureGate(
    keccak256("exclusive_tournament"),
    5000 ether,                 // minStake: 5000 tokens staked
    1,                          // requiredContentId: AND content ID 1
    true,                       // requireBoth: Both required
    true                        // active: true
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
(address content721, address contentStore) = appModuleFactory.deployModules(
    app.appId,
    app.token,
    "BrainFlow Content",
    "BFCNT",
    "ipfs://contract-metadata"
);

// 3. List content
ContentStore store = ContentStore(contentStore);
store.listContent("ipfs://basic-meditation", 25 ether, 0, PaymentTokenType.APP);
store.listContent("ipfs://guided-meditation", 100 ether, 500, PaymentTokenType.APP);

// 4. Set up feature gate
store.setFeatureGate(
    keccak256("advanced_sessions"),
    500 ether,  // minStake
    0,          // requiredContentId
    false,      // requireBoth
    true        // active
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
  address: contentStoreAddress,
  abi: ContentStoreABI,
  functionName: 'checkFeatureAccess',
  args: [userAddress, featureId, userStake, userContentBalance],
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
| InAppContent721 | [src/apps/InAppContent721.sol](../src/apps/InAppContent721.sol) |
| ContentStore | [src/apps/ContentStore.sol](../src/apps/ContentStore.sol) |
| AppStakingVault | [src/apps/AppStakingVault.sol](../src/apps/AppStakingVault.sol) |
| Tournament | [src/apps/Tournament.sol](../src/apps/Tournament.sol) |
| TournamentFactory | [src/apps/TournamentFactory.sol](../src/apps/TournamentFactory.sol) |

## Next Steps

- [TOKENOMICS.md](./TOKENOMICS.md) — Understanding the broader economic design
- [ARCHITECTURE.md](./ARCHITECTURE.md) — How all contracts fit together
- [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md) — Testing your integration locally

