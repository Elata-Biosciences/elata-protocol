# Elata Protocol Summary

This document provides concise summaries and formal specifications of the Elata Protocol for technical review.

## One-Sentence Summary

Elata is a permissionless protocol where anyone can launch app tokens via constant-product bonding curves, with trading fees distributed to app stakers, veELTA holders, and a community-governed treasury.

## One-Paragraph Summary

Elata Protocol enables permissionless app token launches on constant-product bonding curves, funded by ELTA (the native token with 77M max supply). App creators pay 110 ELTA to launch (100 seed liquidity + 10 creation fee); tokens are split 50% to the bonding curve for public sale, 25% to a cliff-then-linear vesting wallet for the team, and 25% to an ecosystem vault for airdrops. Price rises along the curve until 42,000 ELTA is raised, at which point the app "graduates" to a Uniswap V2 LP pair with 2-year locked liquidity. Protocol revenue flows from 1% trading fees on bonding curve trades, which are split 70/15/15 to app stakers, veELTA holders, and treasury respectively. Users earn non-transferable XP through participation, which gates early access to new launches (first 6 hours) and weights votes in funding allocation decisions.

---

## System of Equations

### 1. Bonding Curve Mechanics

The bonding curve implements constant-product automated market making.

**Invariant:**
```
k = reserveElta × reserveToken
```

**Initial State (at launch):**
```
reserveElta₀ = seedElta = 100 ELTA
reserveToken₀ = curveSupply = 5,000,000 tokens (50% of 10M total)
k = 100 × 5,000,000 = 500,000,000
```

**Spot Price:**
```
price = reserveElta / reserveToken
```

**Buy Execution (ELTA → App Token):**
```
Given: eltaIn (amount of ELTA spent)

newReserveElta = reserveElta + eltaIn
newReserveToken = k / newReserveElta
tokensOut = reserveToken - newReserveToken
```

**Sell Execution (App Token → ELTA):**
```
Given: tokensIn (amount of tokens sold)

newReserveToken = reserveToken + tokensIn
newReserveElta = k / newReserveToken
eltaOut = reserveElta - newReserveElta
```

### 2. Fee Calculations

**Trading Fee (1%):**
```
tradingFee = eltaIn × 0.01
totalCost = eltaIn + tradingFee  (buyer pays fee on top)
```

**Sniper Fee (optional, first hour):**
```
if (timestamp < launchTime + 1 hour) AND sniperFeeEnabled:
    sniperFee = eltaIn × 0.05
    totalCost = eltaIn + tradingFee + sniperFee
```

**Fee Distribution:**
```
Given: collectedFees (total ELTA fees)

appStakersShare = collectedFees × 0.70
veEltaShare = collectedFees × 0.15
treasuryShare = collectedFees × 0.15

Invariant: appStakersShare + veEltaShare + treasuryShare = collectedFees
```

### 3. App Token Allocation

**At Launch:**
```
totalSupply = 10,000,000 tokens

curveAllocation = totalSupply × 0.50 = 5,000,000 tokens
vestingAllocation = totalSupply × 0.25 = 2,500,000 tokens
ecosystemAllocation = totalSupply × 0.25 = 2,500,000 tokens

Invariant: curveAllocation + vestingAllocation + ecosystemAllocation = totalSupply
```

**Vesting Schedule:**
```
cliff = 90 days
vestingDuration = 730 days (2 years)

if (timestamp < launchTime + cliff):
    vestedAmount = 0
else:
    elapsed = timestamp - (launchTime + cliff)
    vestedAmount = min(vestingAllocation × elapsed / vestingDuration, vestingAllocation)
```

### 4. Graduation Mechanics

**Graduation Condition:**
```
graduated = (reserveElta >= targetRaisedElta)
         = (reserveElta >= 42,000 ELTA)
```

**LP Pair Creation:**
```
At graduation:
    lpElta = reserveElta (all accumulated ELTA)
    lpTokens = reserveToken (remaining unsold tokens)
    
    LP tokens locked for: lpLockDuration = 730 days (2 years)
    LP beneficiary: app creator
```

### 5. veELTA Staking

**Lock Parameters:**
```
minLockDuration = 7 days
maxLockDuration = 730 days (2 years)
```

**Voting Power Calculation:**
```
Given: lockedAmount, lockDuration

boost = 1 + (lockDuration / maxLockDuration)
      = 1 + (lockDuration / 730 days)

Range: [1.0, 2.0]

votingPower = lockedAmount × boost
```

**Examples:**
```
7-day lock:   boost = 1 + (7/730) ≈ 1.01x
365-day lock: boost = 1 + (365/730) = 1.50x
730-day lock: boost = 1 + (730/730) = 2.00x
```

### 6. XP Gating

**Early Access Gate:**
```
earlyBuyDuration = 6 hours
xpMinForEarlyBuy = 100 XP

if (timestamp < launchTime + earlyBuyDuration):
    require(userXP >= xpMinForEarlyBuy)
```

### 7. Protocol Revenue Model

**Revenue Sources:**
```
1. App Creation Fees:    creationFee = 10 ELTA per launch
2. Trading Fees:         tradingFee = tradeVolume × 0.01
3. App Token Transfer:   transferFee ≤ 2% (optional, per-app)
4. Tournament Rake:      rake = 2.5% of prize pool
5. Content Sales:        protocolFee ≤ 15% of sale price
```

**Aggregate Protocol Revenue:**
```
totalRevenue = Σ(creationFees) + Σ(tradingFees) + Σ(transferFees) + Σ(tournamentRake) + Σ(contentFees)
```

---

## One-Pager: Protocol Overview

### What is Elata?

Elata is a permissionless protocol for launching app tokens with built-in fair distribution, staking rewards, and governance. It combines bonding curve mechanics with a comprehensive fee distribution system that aligns incentives across app developers, token holders, and the protocol treasury.

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                        APP LAUNCH FLOW                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Creator pays 110 ELTA ──► AppFactory deploys:                │
│                              ├─ AppToken (10M supply)          │
│                              ├─ AppBondingCurve                │
│                              ├─ AppStakingVault                │
│                              ├─ AppVestingWallet (25%)         │
│                              └─ AppEcosystemVault (25%)        │
│                                                                 │
│   Bonding Curve receives 50% of tokens + 100 ELTA seed         │
│                                                                 │
│   Buyers exchange ELTA for tokens along x*y=k curve            │
│   Price rises with each purchase                               │
│                                                                 │
│   When 42,000 ELTA raised ──► Graduation:                      │
│                               └─ Create Uniswap LP pair        │
│                               └─ Lock LP tokens for 2 years    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Revenue Model

The protocol generates revenue through multiple streams:

| Source | Rate | Flow |
|--------|------|------|
| App Creation | 10 ELTA/launch | FeeCollector → FeeManager |
| Trading Fees | 1% per trade | FeeCollector → RewardsDistributor |
| Transfer Fees | 0-2% (optional) | AppToken → RewardsDistributor |
| Tournament Rake | 2.5% | Tournament → AppFeeRouter |
| Content Sales | Up to 15% | ContentStore → FeeCollector |

### Fee Distribution

All protocol fees flow through the RewardsDistributor:

```
                    ┌──────────────────┐
                    │ Collected Fees   │
                    └────────┬─────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
   │ App Stakers │    │   veELTA    │    │  Treasury   │
   │    70%      │    │    15%      │    │    15%      │
   └─────────────┘    └─────────────┘    └─────────────┘
```

### Economic Flywheel

1. **App Launch** → Creator pays ELTA → Protocol earns creation fee
2. **Trading Activity** → Users trade on curve → Protocol earns trading fees
3. **Fee Distribution** → Fees split to stakers → Incentivizes staking
4. **Staking Rewards** → Stakers earn yield → Increases TVL
5. **Governance Power** → veELTA holders vote → Protocol improvement
6. **Better Protocol** → More app launches → Cycle repeats

### Key Invariants

These properties must always hold:

| Invariant | Description |
|-----------|-------------|
| `k = x × y` | Bonding curve constant product preserved |
| `fees_out ≤ fees_in` | Cannot distribute more than collected |
| `ELTA.totalSupply() ≤ 77M` | Supply cap enforced |
| `splits = 70 + 15 + 15 = 100%` | Fee splits sum to 100% |
| `lockDuration ∈ [7, 730] days` | Staking within bounds |

### Security Properties

- **Non-upgradeable**: All contracts are immutable after deployment
- **Role-based access**: Admin functions require multisig approval
- **Supply cap enforcement**: ELTA minting capped at 77M
- **Time-locked governance**: 48-hour delay on proposal execution
- **LP lock**: Graduated liquidity locked for 2 years

### Key Parameters

```
ELTA Supply Cap:         77,000,000 tokens
App Token Supply:        10,000,000 tokens per app
Seed Liquidity:          100 ELTA
Creation Fee:            10 ELTA
Graduation Threshold:    42,000 ELTA
LP Lock Duration:        730 days (2 years)
veELTA Lock Range:       7 - 730 days
veELTA Boost Range:      1x - 2x
Trading Fee:             1%
Revenue Split:           70% app / 15% veELTA / 15% treasury
Governance Quorum:       4% of veELTA supply
Proposal Threshold:      0.1% of veELTA supply
Timelock Delay:          48 hours
```

### Governance

Two complementary governance mechanisms:

1. **Protocol Governance (veELTA)**: Parameter changes, treasury allocation, emergency actions
2. **Funding Decisions (XP)**: App experiment funding weighted by participation reputation

---

*For implementation details, see [ARCHITECTURE.md](./ARCHITECTURE.md) and [TOKENOMICS.md](./TOKENOMICS.md).*
