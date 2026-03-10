# Tokenomics

This document summarizes the current on-chain token and fee mechanics.

## ELTA Token

ELTA is the base protocol token.

### Supply

- **Maximum supply**: `77,000,000 ELTA`
- **Mint behavior**: minted once at deployment to treasury
- **Inflation**: none in current implementation

ELTA is used for:

1. app launch costs
2. bonding-curve purchases
3. governance/staking via veELTA

## veELTA Staking

Users lock ELTA to receive non-transferable veELTA voting power.

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
| 1,000 ELTA | 7 days | ~1.01x | ~1,010 veELTA |
| 1,000 ELTA | 365 days | 1.50x | 1,500 veELTA |
| 1,000 ELTA | 730 days | 2.00x | 2,000 veELTA |

### Lock Operations

- **Create lock**: Deposit ELTA with an unlock timestamp
- **Increase amount**: Add more ELTA to an existing lock
- **Extend lock**: Push the unlock timestamp further out
- **Unlock**: After expiry, withdraw your original ELTA

veELTA is non-transferable. Holders can increase amount and extend lock, then unlock principal at expiry.

## XP Reputation

XP is non-transferable participation reputation.

Current launch-related behavior:

- default early-buy gate: `100 XP`
- gate window: first `6 hours` from launch timestamp

## App Launch Economics

### Launch Cost

Per app launch:

| Component | Amount |
|---|---|
| Creation fee | 10 ELTA |
| Curve seed | 100 ELTA |
| Total | 110 ELTA |

### App Token Supply

Each app token mints exactly `10,000,000` units at launch:

- `50%` -> bonding curve
- `25%` -> vesting wallet
- `25%` -> ecosystem vault

Creator allocation is vesting-based (not auto-staked by default contract flow).

## Revenue and Distribution

The current repository has two fee-era contracts; docs here follow the active V2 routing path.

### Revenue Sources

| Source | Current behavior |
|---|---|
| Launch fee | `LAUNCH_FEE` fee kind |
| Curve trading fee | fee bps from `AppFeeRouter` (default `1%`) |
| Transfer tax | LP-keyed in `AppToken` (default `1%`, max `2%`) |
| Module fees | `CONTENT_SALE`, `TOURNAMENT_FEE`, `OTHER` fee kinds |

### Routing Policy (V2)

`FeeCollector` accumulates balances by app/kind/asset, then `FeeSwapper` routes:

```
if appPaused:
    100% treasury
elif feeKind == LAUNCH_FEE:
    100% treasury
else:
    default 80% contributorSplit
    default 20% treasury
```

### Bonding Curve

The bonding curve provides price discovery without requiring initial liquidity provision:

1. Price starts low and increases as more tokens are bought
2. Trading fee is charged on top of the buy amount
3. Fee accumulates and is swept into the fee pipeline
4. Curve lifecycle includes activation, cancellation, graduation, and forced graduation

### Graduation

When reserve reaches target (`42,000 ELTA` default), the curve graduates:

1. Remaining tokens and ELTA form a liquidity pair
2. LP tokens are locked for 2 years
3. Trading moves to the DEX

### Transfer Fees (Optional)

App tokens can charge transfer tax on LP interactions only.

Default parameters:

- `transferFeeBps = 100`
- `MAX_TRANSFER_FEE_BPS = 200`
- fee applies only when transfer involves allowlisted LP and neither side is exempt

## Security Considerations

Key protections in current economics path:

1. fixed ELTA supply
2. explicit curve states and deadline/force-graduate
3. explicit fee-kind taxonomy
4. per-app fee accounting and permissionless sweeps
5. LP-keyed (not blanket) transfer taxation

## Contract References

| Contract | Source |
|----------|--------|
| ELTA | [lib/ELTA/src/ELTA.sol](../lib/ELTA/src/ELTA.sol) |
| VeELTA | [src/staking/VeELTA.sol](../src/staking/VeELTA.sol) |
| ElataPoints | [src/experience/ElataPoints.sol](../src/experience/ElataPoints.sol) |
| AppFactory | [src/apps/AppFactory.sol](../src/apps/AppFactory.sol) |
| AppBondingCurve | [src/apps/AppBondingCurve.sol](../src/apps/AppBondingCurve.sol) |
| FeeCollector | [src/fees/FeeCollector.sol](../src/fees/FeeCollector.sol) |
| FeeSwapper | [src/fees/FeeSwapper.sol](../src/fees/FeeSwapper.sol) |

