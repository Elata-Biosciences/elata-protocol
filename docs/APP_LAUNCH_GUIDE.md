# App Launch Guide

This guide covers the current two-phase app launch path in `AppFactory`.

## Overview

The protocol supports:

1. **Phase A**: register app metadata + owner safe (no token yet)
2. **Phase B**: launch token stack for that app ID

Legacy one-call `createApp(...)` still works and performs both phases.

## Prerequisites

- Local environment running
- ELTA approved for launch operations
- Owner safe address to control app config

## Launch Costs and Defaults

| Parameter | Value |
|---|---|
| App creation fee | `10 ELTA` |
| Curve seed | `100 ELTA` |
| Total paid for full launch | `110 ELTA` |
| App token supply | `10,000,000` |
| Allocation | `50%` curve, `25%` vesting, `25%` ecosystem |
| Graduation target | `42,000 ELTA` |
| LP lock default | `730 days` |

## Phase A: Register App (No Token Yet)

```solidity
ELTA.approve(address(appFactory), 10 ether);

(uint256 appId,) = appFactory.createAppWithoutToken(
    ownerSafe,
    "ipfs://app-metadata",
    contributors
);
```

What this does:

- charges launch fee
- deploys `ContributorSplit`
- registers app in `AppRegistry`

## Phase B: Launch Token For Existing App

```solidity
ELTA.approve(address(appFactory), 100 ether);

(address token, address curve) = appFactory.launchTokenForApp(
    appId,
    "Neuro App Token",
    "NEURO",
    0,          // 0 = default 10,000,000
    operators
);
```

What this deploys:

- `AppToken`
- `AppBondingCurve`
- `AppStakingVault`
- `AppVestingWallet`
- `AppEcosystemVault`

## Legacy One-Call Path

`createApp(...)` still exists and internally runs both phases:

1. fee collection + registration
2. seed collection + token launch

## Post-Launch Validation Checklist

- app exists in `AppRegistry`
- `tokenLaunched == true`
- curve reserves initialized with seed and curve allocation
- fee collector configured on token and curve
- operator/admin roles assigned correctly

## Trading Behavior Notes

- curve must be activated after delay
- early-buy gate defaults to `100 XP` for `6 hours`
- curve buy fee comes from `AppFeeRouter.feeBps()` (default `1%`)
- fees are accumulated and swept into `FeeCollector`

## Graduation Behavior

Graduation happens when target is reached (or forced at deadline):

- Uniswap V2 pair created/used
- reserve assets added as LP
- LP locked in `LpLocker`
- factory receives graduation callback

## Common Mistakes

- forgetting to approve ELTA separately for fee and seed steps
- assuming creator allocation is auto-staked (it is vesting + ecosystem buckets in current factory flow)
- forgetting to activate a pending curve before trading
- setting no fee collector, which breaks transfer-tax routing expectations

## Contract References

| Contract | Source |
|----------|--------|
| AppFactory | [src/apps/AppFactory.sol](../src/apps/AppFactory.sol) |
| AppToken | [src/apps/AppToken.sol](../src/apps/AppToken.sol) |
| AppBondingCurve | [src/apps/AppBondingCurve.sol](../src/apps/AppBondingCurve.sol) |
| AppRegistry | [src/registry/AppRegistry.sol](../src/registry/AppRegistry.sol) |
| ContributorSplit | [src/contributors/ContributorSplit.sol](../src/contributors/ContributorSplit.sol) |
| FeeCollector | [src/fees/FeeCollector.sol](../src/fees/FeeCollector.sol) |
| AppStakingVault | [src/apps/AppStakingVault.sol](../src/apps/AppStakingVault.sol) |

## Next Steps

- [TOKENOMICS.md](./TOKENOMICS.md) — Understanding the broader economic design
- [ARCHITECTURE.md](./ARCHITECTURE.md) — How all contracts fit together
- [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md) — Testing your integration locally

