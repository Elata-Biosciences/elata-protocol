# Tokenomics

This document describes the economic design of the Elata Protocol: how ELTA tokens work, how value flows through the system, and how the incentives align participants toward long-term ecosystem growth.

## ELTA Token

ELTA is the governance and utility token for the Elata ecosystem.

### Supply

- **Maximum supply**: 77,000,000 ELTA (hard cap, enforced in contract)
- **Initial mint**: 10,000,000 ELTA to treasury
- **Remaining**: 67,000,000 ELTA available for future minting via governance

The supply cap is immutable. Once set at deployment, it cannot be changed. Minting requires the `MINTER_ROLE`, which is initially held by the admin multisig and can be assigned or revoked through governance.

### Token Properties

ELTA is a standard ERC20 with these extensions:

| Feature | Description |
|---------|-------------|
| ERC20Votes | On-chain governance delegation |
| ERC20Permit | Gasless approvals via signatures |
| Burnable | Anyone can burn their own tokens |
| No transfer fees | Compatible with all DeFi infrastructure |

The token has no transfer taxes, rebasing mechanics, or other non-standard behaviors. It works with any DEX, aggregator, or DeFi protocol expecting a standard ERC20.

### Token Utility

ELTA serves three primary functions:

1. **Governance** — Stake ELTA to receive veELTA voting power for protocol decisions
2. **App launches** — Pay ELTA to create new app tokens on the platform
3. **Economic base** — All app token trading uses ELTA as the quote currency

## veELTA Staking

Users lock ELTA to receive veELTA, a non-transferable token that represents voting power and entitles holders to protocol revenue.

### Lock Parameters

| Parameter | Value |
|-----------|-------|
| Minimum lock | 7 days |
| Maximum lock | 730 days (2 years) |
| Minimum boost | 1.0x |
| Maximum boost | 2.0x |

### How Boost Works

Longer locks give more veELTA per ELTA locked. The boost scales linearly:

```
boost = 1 + (lock_duration / max_lock)
veELTA = ELTA_locked × boost
```

Examples:

| Lock Amount | Lock Duration | Boost | veELTA Received |
|-------------|---------------|-------|-----------------|
| 1,000 ELTA | 7 days (min) | 1.00x | 1,000 veELTA |
| 1,000 ELTA | 365 days | 1.50x | 1,500 veELTA |
| 1,000 ELTA | 730 days (max) | 2.00x | 2,000 veELTA |

### Lock Operations

- **Create lock**: Deposit ELTA with an unlock timestamp
- **Increase amount**: Add more ELTA to an existing lock
- **Extend lock**: Push the unlock timestamp further out
- **Unlock**: After expiry, withdraw your original ELTA

veELTA is non-transferable to prevent vote buying. You can't sell or delegate your position to another address.

### Why Time-Locked Staking?

Time locks serve multiple purposes:

1. **Governance alignment** — Long-term stakers have more say in decisions that affect the protocol's future
2. **Attack resistance** — Can't flash-loan ELTA to manipulate votes
3. **Supply predictability** — Locked tokens create predictable circulation

## XP Reputation

XP (Experience Points) is a non-transferable reputation token that tracks user participation.

### Earning XP

XP is awarded for activities that benefit the ecosystem:

- Submitting EEG data sessions
- Playing apps and completing activities
- Participating in tournaments
- Voting in funding rounds
- Contributing to governance

The exact amounts are set by XP operators and can vary based on activity type and quality.

### Using XP

XP determines voting weight in funding decisions. When the community votes on which app experiments to fund, votes are weighted by XP rather than ELTA. This means funding decisions reflect participation, not just capital.

XP also gates early access to new app launches. For the first 6 hours after an app launches, only users with sufficient XP (default: 100 XP) can buy tokens. This rewards active community members.

### XP vs ELTA

The protocol separates reputation (XP) from ownership (ELTA) intentionally:

| Aspect | XP | ELTA |
|--------|-----|------|
| Transferable | No | Yes |
| Earned by | Participation | Purchase or earnings |
| Used for | Funding votes, early access | Governance, staking, trading |
| Represents | Contribution | Economic stake |

This separation prevents plutocracy. You can't simply buy XP to control funding decisions—you have to earn it through genuine participation.

## Revenue and Distribution

Protocol revenue comes from fees on economic activity and flows back to participants.

### Revenue Sources

| Source | Fee | Description |
|--------|-----|-------------|
| Trading fees | 1% | On bonding curve buys and sells |
| Tournament rake | 2.5% | Protocol share of tournament prizes |
| App transfer fees | 1% | On app token transfers (optional) |

### Distribution Split

All revenue flows through the RewardsDistributor, which splits it:

```
Incoming Fees
├── 70% → App token stakers
├── 15% → veELTA holders
└── 15% → Treasury
```

This split is fixed in the contract. Changes require governance approval.

### How Claims Work

veELTA holders can claim their share of accumulated fees. The distributor takes snapshots of veELTA balances, and claims are proportional to your share of total veELTA at each snapshot.

App token stakers earn through their app's AppRewardsDistributor, which works similarly but tracks stakes in individual app tokens.

### Example

Monthly trading volume: 100,000 ELTA

```
Trading fee (1%):     1,000 ELTA

Distribution:
├── App stakers:      700 ELTA (70%)
├── veELTA holders:   150 ELTA (15%)
└── Treasury:         150 ELTA (15%)
```

## App Launch Economics

Developers can launch app tokens with built-in economic infrastructure.

### Launch Costs

To create an app:

| Cost | Amount | Purpose |
|------|--------|---------|
| Seed liquidity | 100 ELTA | Initial bonding curve liquidity |
| Creation fee | 10 ELTA | Protocol fee to treasury |
| **Total** | 110 ELTA | |

### Token Distribution

Each app token has 1 billion total supply, distributed:

- **50% to creator** — Auto-staked in the app's staking vault
- **50% to bonding curve** — Available for public trading

The creator's tokens are auto-staked, meaning they earn rewards but can't immediately dump. To sell, they must unstake first, which is visible on-chain.

### Bonding Curve

The bonding curve provides price discovery without requiring initial liquidity provision:

1. Price starts low and increases as more tokens are bought
2. 1% fee on each trade goes to the RewardsDistributor
3. Anyone can buy or sell at any time

### Graduation

When the bonding curve accumulates 42,000 ELTA, it "graduates":

1. Remaining tokens and ELTA form a liquidity pair
2. LP tokens are locked for 2 years
3. Trading moves to the DEX

This graduation mechanism ensures every successful app has permanent liquidity.

### Transfer Fees (Optional)

App tokens can optionally charge a 1% transfer fee (governance-adjustable, max 2%). This fee follows the same 70/15/15 distribution split, creating ongoing rewards for stakers.

Certain addresses are exempt from transfer fees to prevent circular fee issues: the bonding curve, staking vault, and factory contracts.

## Economic Flywheel

The token economics create a reinforcing cycle:

```
Users play apps
    ↓
Generate data and usage
    ↓
Protocol captures fees
    ↓
Community votes on funding
    ↓
App experiments and development funded
    ↓
Better apps built
    ↓
More users play apps
```

Simultaneously:

```
Protocol captures fees
    ↓
Distributed to stakers
    ↓
Attracts long-term holders
    ↓
Better governance decisions
    ↓
Protocol improves
    ↓
More fee generation
```

The key insight is that XP guides *what* gets funded (through voting), while ELTA staking captures *the value* of that funding (through yield).

## Governance Parameters

The Governor contract controls protocol changes:

| Parameter | Value |
|-----------|-------|
| Voting delay | 1 day |
| Voting period | 7 days |
| Proposal threshold | 0.1% of supply (~77,000 ELTA) |
| Quorum | 4% of supply (~3.08M ELTA) |

**Emergency proposals** require 5% of supply to propose but have an expedited 3-day voting period for critical fixes.

## Security Considerations

The economic design includes several security measures:

1. **Supply cap** — Cannot mint beyond 77M ELTA, preventing inflation attacks
2. **Time-locked staking** — Prevents flash-loan governance attacks
3. **Non-transferable XP** — Prevents reputation buying
4. **Locked liquidity** — Graduated app tokens have permanently locked LP
5. **Role-based minting** — Only authorized addresses can mint ELTA

## Contract References

| Contract | Source |
|----------|--------|
| ELTA | [lib/ELTA/src/ELTA.sol](../lib/ELTA/src/ELTA.sol) |
| VeELTA | [src/staking/VeELTA.sol](../src/staking/VeELTA.sol) |
| ElataPoints | [src/experience/ElataPoints.sol](../src/experience/ElataPoints.sol) |
| RewardsDistributor | [src/rewards/RewardsDistributor.sol](../src/rewards/RewardsDistributor.sol) |
| AppFactory | [src/apps/AppFactory.sol](../src/apps/AppFactory.sol) |
| AppBondingCurve | [src/apps/AppBondingCurve.sol](../src/apps/AppBondingCurve.sol) |

