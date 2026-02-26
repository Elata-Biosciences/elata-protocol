# Elata Protocol Event Reference

This file lists key events and signatures used by the current contracts.

## Indexing Guidelines

- Track by indexed keys: `appId`, `kind`, `asset`, `user`, `epochId`.
- Prioritize lifecycle and fee-routing events for protocol dashboards.

## App Lifecycle Events

### AppFactory (`AppFactory.sol`)

| Event Signature | Notes |
|---|---|
| `AppCreated(uint256 appId, address creator, address token, address vault, address curve, address vestingWallet, address ecosystemVault, uint256 curveShare)` | Emitted on token launch |
| `AppGraduated(uint256 appId, address token, address pair, address locker, uint256 unlockAt, uint256 totalRaised, uint256 finalSupply)` | Emitted when curve graduates |

### AppRegistry (`AppRegistry.sol`)

| Event Signature | Notes |
|---|---|
| `AppRegistered(uint256 appId, address ownerSafe, address contributorSplit, string metadataURI)` | App created without token |
| `AppTokenLaunched(uint256 appId, address appToken, address bondingCurve)` | Phase B completed |
| `AppPaused(uint256 appId, bool paused)` | Affects fee routing in `FeeSwapper` |

### AppBondingCurve (`AppBondingCurve.sol`)

| Event Signature | Notes |
|---|---|
| `CurveInitialized(uint256 appId, uint256 seedElta, uint256 tokenSupply, uint256 initialK)` | Initial reserves set |
| `TokensPurchased(uint256 appId, address buyer, uint256 eltaIn, uint256 tokensOut, uint256 newReserveElta, uint256 newReserveToken, uint256 newPrice)` | Buy execution |
| `StateChanged(uint256 appId, CurveState oldState, CurveState newState)` | State transitions |
| `CurveActivated(uint256 appId, uint256 activationTime, uint256 deadline)` | PENDING -> ACTIVE |
| `CurveCancelled(uint256 appId, uint256 eltaRefunded, uint256 tokensRefunded)` | Creator pre-activation cancel |
| `ForceGraduated(uint256 appId, uint256 eltaRaised)` | Deadline-triggered graduation |
| `AppGraduated(uint256 appId, address token, address pair, address locker, uint256 unlockAt, uint256 totalRaisedElta, uint256 tokensToLp)` | LP formed and locked |
| `FeesSwepted(uint256 appId, uint256 amount, address feeCollector)` | Trading fees swept |

### AppToken (`AppToken.sol`)

| Event Signature | Notes |
|---|---|
| `Minted(address to, uint256 amount)` | Launch allocations |
| `TransferFeeUpdated(uint16 oldBps, uint16 newBps)` | Transfer tax bps |
| `TransferFeeExemptSet(address account, bool exempt)` | Tax exemptions |
| `LPAddressUpdated(address lp, bool isLP)` | LP tax allowlist |
| `FeeCollectorUpdated(address oldCollector, address newCollector, uint256 appId)` | Fee sink target |
| `TransferTaxCollected(uint256 appId, address token, uint256 amount, address from, address to)` | LP-keyed tax collection |

## Fee Pipeline Events

### FeeCollector (`FeeCollector.sol`)

| Event Signature | Notes |
|---|---|
| `EltaDeposited(uint256 appId, FeeKind kind, uint256 amount, address from)` | ELTA bucketed by kind |
| `AppTokenDeposited(uint256 appId, FeeKind kind, address token, uint256 amount, address from)` | App-token bucketed by kind |
| `EltaSwept(uint256 appId, FeeKind kind, uint256 amount, address to, address sweeper)` | Forwarded to router |
| `AppTokenSwept(uint256 appId, FeeKind kind, address token, uint256 amount, address to, address sweeper)` | Forwarded to router |

### FeeSwapper (`FeeSwapper.sol`, `IFeeRouterV2`)

| Event Signature | Notes |
|---|---|
| `FeeAccrued(uint256 appId, FeeKind kind, address asset, uint256 amount, address payer)` | Incoming routed amount |
| `FeeRoutedToTreasury(uint256 appId, FeeKind kind, address asset, uint256 amount)` | Treasury leg |
| `FeeRoutedToContributors(uint256 appId, FeeKind kind, address asset, uint256 contributorsAmount, address contributorSplit)` | Contributor leg |
| `Swapped(uint256 appId, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut, address caller)` | Swap helper path |

### ContributorSplit (`ContributorSplit.sol`)

| Event Signature | Notes |
|---|---|
| `PaymentReceived(uint256 appId, FeeKind kind, address asset, uint256 amount, address from)` | Received from router |
| `PaymentReleased(uint256 appId, address asset, address account, uint256 amount)` | Contributor claim |

## Governance and Config Events

### ProtocolConfig (`ProtocolConfig.sol`)

Use this contract's update events as canonical configuration change feed:

- `AppCreationFeeUpdated`
- `AppCreationSeedUpdated`
- `BondingCurveTaxUpdated`
- `GraduationTargetUpdated`
- `LpLockDurationUpdated`
- `ActivationDelayUpdated`
- `MaxCurveDurationUpdated`
- `AppTransferTaxUpdated`
- `MaxAppTransferTaxUpdated`
- `FeeSplitsUpdated`
- `EpochLengthUpdated`
- `RouterAllowlisted`
- `TreasuryUpdated`

### Governor/Timelock (`ElataGovernor.sol`, `ElataTimelock.sol`)

Track standard OpenZeppelin governor lifecycle events plus any custom emergency proposal events.

## Staking and Reputation Events

### VeELTA (`VeELTA.sol`)

- `Locked`
- `AmountIncreased`
- `LockExtended`
- `Unlocked`

### ElataPoints (`ElataPoints.sol`)

Track XP award/revoke/claim events for participation analytics.
