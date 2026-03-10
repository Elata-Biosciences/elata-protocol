# Elata Protocol Summary

This document defines the current protocol behavior from deployed contracts and tests.

## One-Sentence Summary

Elata is a permissionless app-launch protocol where app tokens are sold on a constant-product ELTA bonding curve, then routed into a fee pipeline that sends launch fees to treasury and app revenue to contributor splits plus treasury.

## One-Paragraph Summary

An app launch costs `110 ELTA` (`100` seed + `10` launch fee). `AppFactory` deploys an app stack (`AppToken`, `AppBondingCurve`, `AppStakingVault`, `AppVestingWallet`, `AppEcosystemVault`) and mints exactly `10,000,000` app tokens split `50%` curve, `25%` vesting wallet, `25%` ecosystem vault. The curve follows `x*y=k`, supports buys while active, and graduates at `42,000 ELTA` (or can be force-graduated at deadline), creating a Uniswap V2 pair with LP locked for `730 days`. Trading and LP-keyed transfer taxes flow through `FeeCollector` and `FeeSwapper`: `LAUNCH_FEE` routes `100%` to treasury, while app-revenue fee kinds route to contributor split + treasury (default `80/20`, governance-configurable). ELTA has a fixed `77,000,000` supply cap minted at deployment, veELTA lock boost ranges from `1x` to `2x`, and XP gates early buys by default (`100 XP` for first `6 hours`).

---

## System of Equations

### 1. Bonding Curve

Invariant:

```
k = reserveElta * reserveToken
```

Initialization defaults:

```
reserveElta0 = 100 ELTA
reserveToken0 = 5,000,000 APP
k0 = reserveElta0 * reserveToken0
```

Buy path:

```
newReserveElta = reserveElta + eltaIn
newReserveToken = k / newReserveElta
tokensOut = reserveToken - newReserveToken
```

Spot price approximation:

```
price ~= reserveElta / reserveToken
```

### 2. Bonding-Curve Trading Fee

Base trade fee from `AppFeeRouter.feeBps()` (default `100 bps`):

```
tradingFee = actualEltaIn * feeBps / 10_000
buyerPays = actualEltaIn + tradingFee
```

Optional sniper add-on (default disabled):

```
if sniperFeeEnabled and now < activationTime + sniperFeeDuration:
    effectiveFeeBps = feeBps + sniperFeeBps
```

### 3. Token Supply and Launch Allocation

Per-app supply:

```
totalSupply = 10,000,000 APP
curveShare = 50%
teamVestingShare = 25%
ecosystemShare = 25%
```

Conservation:

```
curveShare + teamVestingShare + ecosystemShare = totalSupply
```

### 4. Graduation Rules

Target graduation:

```
graduate when reserveElta >= 42,000 ELTA
```

Forced graduation:

```
deadline = activationTime + maxCurveDuration
if now >= deadline and state not in {GRADUATED, CANCELLED}:
    forceGraduate()
```

LP lock:

```
lpUnlockAt = graduationTimestamp + 730 days   // default
```

### 5. veELTA Voting Power

Lock window:

```
minLock = 7 days
maxLock = 730 days
```

Boost:

```
boost = 1 + duration / maxLockDuration
votingPower = lockedAmount * boost
boost range: [1x, 2x]
```

### 6. Fee Routing Policy (Current V2 Pipeline)

`FeeCollector` tracks pending balances by `(appId, feeKind, asset)` and sweeps to `FeeSwapper`.

Routing policy:

```
if appPaused:
    100% treasury
else if kind == LAUNCH_FEE:
    100% treasury
else:
    treasury = amount * treasuryTakeBps / 10_000      // default 2000 bps
    contributors = amount - treasury                  // default 8000 bps
```

Where `contributors` is forwarded to the app's `ContributorSplit`.

### 7. XP Early Access Gate

Defaults:

```
xpMinForEarlyBuy = 100 XP
earlyBuyDuration = 6 hours
```

Constraint:

```
if now < launchTimestamp + earlyBuyDuration:
    require(userXP >= xpMinForEarlyBuy)
```

---

## One-Pager

### Core Flow

1. Developer registers app and launches token via `AppFactory`.
2. Pays `10 ELTA` launch fee + `100 ELTA` curve seed.
3. App token (`10,000,000`) is minted as `50/25/25` curve/vesting/ecosystem.
4. Buyers purchase from active bonding curve (`x*y=k`).
5. Trading fees and LP-keyed transfer taxes accumulate and are swept to `FeeCollector`.
6. `FeeSwapper` routes by fee kind:
   - `LAUNCH_FEE`: `100%` treasury
   - App revenue kinds: default `80%` contributor split / `20%` treasury
7. At `42,000 ELTA` (or deadline), curve graduates to Uniswap LP and locks LP.

### Key Constants (Defaults)

| Parameter | Value |
|---|---|
| ELTA max supply | `77,000,000` |
| App launch total | `110 ELTA` |
| App creation fee | `10 ELTA` |
| Curve seed | `100 ELTA` |
| App token supply | `10,000,000` |
| Curve graduation target | `42,000 ELTA` |
| LP lock duration | `730 days` |
| XP early gate | `100 XP`, first `6h` |
| Base trade fee | `1%` (`100 bps`) |

### Invariants To Preserve

- `k = x*y` for curve math (within integer rounding behavior).
- Curve lifecycle is monotonic: `PENDING -> ACTIVE -> GRADUATED` or `PENDING -> CANCELLED`.
- `AppToken.transferFeeBps <= 200 bps`.
- Fee routing never exceeds incoming amount.
- ELTA total supply remains fixed at `77,000,000`.

---

For deeper contract mapping, see [ARCHITECTURE.md](./ARCHITECTURE.md) and [TOKENOMICS.md](./TOKENOMICS.md).
