# Elata Protocol Event Reference

This document catalogs all events emitted by Elata Protocol contracts for indexer and frontend integration.

## Indexing Guidelines

Events are designed for efficient indexing:
- `indexed` parameters enable topic-based filtering
- First 3 parameters can be indexed (Solidity limit)
- Common indexed fields: `appId`, `user`, `token`, `epochId`

## Core Protocol Events

### ELTA Token (`ELTA.sol`)
Standard ERC20 events only (Transfer, Approval).

### VeELTA Staking (`VeELTA.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `Locked(user, amount, unlockTime, veELTA)` | `user` | User locked ELTA to receive veELTA |
| `AmountIncreased(user, addAmount, newPrincipal, newVeELTA)` | `user` | User added more ELTA to existing lock |
| `LockExtended(user, oldUnlockTime, newUnlockTime, newVeELTA)` | `user` | User extended lock duration |
| `Unlocked(user, principal, veELTABurned)` | `user` | User unlocked expired position |

### Elata Points (`ElataPoints.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `PointsAwarded(user, amount)` | `user` | XP points awarded to user |
| `PointsRevoked(user, amount)` | `user` | XP points revoked from user |
| `MerkleRootUpdated(distributionId, merkleRoot, dataHash)` | `distributionId` | Merkle airdrop distribution created |
| `PointsClaimed(distributionId, user, amount)` | `distributionId`, `user` | User claimed XP from merkle distribution |

## App Lifecycle Events

### AppFactory (`AppFactory.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `AppCreated(appId, creator, token, curve, vault, lpLocker, name, symbol, imageURI, initialSupply)` | `appId`, `creator`, `token` | New app deployed |
| `AppGraduated(appId, creator, lp, lpAmount, lockedUntil)` | `appId`, `creator` | App graduated from bonding curve |

### AppBondingCurve (`AppBondingCurve.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `CurveInitialized(appId, seedElta, tokenSupply, initialK)` | `appId` | Bonding curve initialized |
| `XPGateUpdated(minXP, duration)` | - | XP gate configuration changed |
| `SniperFeeConfigUpdated(feeBps, duration, enabled)` | - | Sniper protection settings changed |
| `TokensPurchased(appId, buyer, eltaIn, tokensOut, fee, newK, newTokenReserve)` | `appId`, `buyer` | User bought tokens |
| `AppGraduated(appId, totalEltaCollected, lpEltaPaired, tokensReleased, lpCreated, lpTokensLocked)` | `appId` | Curve graduated to DEX |
| `StateChanged(appId, oldState, newState)` | `appId` | Curve state transition |
| `CurveActivated(appId, activationTime, deadline)` | `appId` | Curve became active for trading |
| `CurveCancelled(appId, eltaRefunded, tokensRefunded)` | `appId` | Curve cancelled, funds returned |
| `ForceGraduated(appId, eltaRaised)` | `appId` | Governance force-graduated curve |
| `FeesSwepted(appId, amount, feeCollector)` | `appId`, `feeCollector` | Pending fees sent to collector |
| `FeeCollectorUpdated(oldCollector, newCollector)` | `oldCollector`, `newCollector` | Fee collector address changed |
| `ReferralRegistryUpdated(oldRegistry, newRegistry)` | `oldRegistry`, `newRegistry` | Referral registry changed |

### AppToken (`AppToken.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `AppMetadataUpdated(description, imageURI, website)` | - | App token metadata changed |
| `MintingFinalized()` | - | Token minting permanently disabled |
| `Minted(to, amount)` | `to` | Tokens minted |
| `TransferFeeUpdated(oldBps, newBps)` | - | Transfer fee changed |
| `BurnFeeBpsUpdated(oldBps, newBps)` | - | Burn fee changed |
| `TransferFeeExemptSet(account, exempt)` | `account` | Fee exemption status changed |
| `LPAddressUpdated(lp, isLP)` | `lp` | LP pair registration updated |
| `FeeCollectorUpdated(oldCollector, newCollector, appId)` | `oldCollector`, `newCollector` | Fee collector changed |
| `TransferTaxCollected(appId, token, amount, from, to)` | `appId`, `token` | Transfer tax collected |
| `TransferFeeCollected(appId, token, amount, feeCollector, burnAmount)` | `appId`, `token` | Transfer fees distributed |

### AppStakingVault (`AppStakingVault.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `Staked(user, amount, newBalance)` | `user` | User staked app tokens |
| `Unstaked(user, amount, newBalance)` | `user` | User unstaked app tokens |
| `StakedFor(beneficiary, amount, staker)` | `beneficiary`, `staker` | Tokens staked on behalf of another |

### LpLocker (`LpLocker.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `LpLocked(appId, lpToken, beneficiary, unlockAt, amount)` | `appId` | LP tokens locked |
| `LpClaimed(appId, beneficiary, amount)` | `appId` | Creator claimed unlocked LP |

## Reward Distribution Events

### RewardsDistributor (`RewardsDistributor.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `RevenueSplit(appId, appStakers, veEltaHolders, treasury)` | `appId` | Revenue split among recipients |
| `VeEpochCreated(epochId, blockNumber, amount)` | `epochId` | New veELTA reward epoch |
| `VeRewardsClaimed(user, fromEpoch, toEpoch, amount)` | `user` | User claimed veELTA rewards |
| `VeTokenEpochCreated(token, epochId, blockNumber, amount)` | `token`, `epochId` | Token rewards epoch created |
| `VeTokenRewardsClaimed(token, user, fromEpoch, toEpoch, amount)` | `token`, `user` | User claimed token rewards |
| `TreasuryUpdated(oldTreasury, newTreasury)` | `oldTreasury`, `newTreasury` | Treasury address changed |
| `EmergencyPause(paused)` | - | Emergency pause toggled |

### AppRewardsDistributor (`AppRewardsDistributor.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `AppRegistered(vault)` | `vault` | App staking vault registered |
| `AppPaused(vault, paused)` | `vault` | App reward distribution paused |
| `AppRemoved(vault)` | `vault` | App removed from distribution |
| `AppDistributed(blockNumber, totalAmount, activeApps)` | `blockNumber` | Rewards distributed to apps |
| `AppClaim(vault, user, fromEpoch, toEpoch, amount)` | `vault`, `user` | User claimed app staking rewards |

## Fee Management Events

### FeeCollector (`FeeCollector.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `EltaDeposited(appId, amount, from)` | `appId`, `from` | ELTA fees deposited |
| `AppTokenDeposited(appId, token, amount, from)` | `appId`, `token`, `from` | App token fees deposited |
| `EltaSwept(appId, amount, to)` | `appId`, `to` | ELTA swept to fee manager |
| `AppTokenSwept(appId, token, amount, to)` | `appId`, `token`, `to` | App tokens swept |
| `FeeManagerUpdated(oldFeeManager, newFeeManager)` | `oldFeeManager`, `newFeeManager` | Fee manager changed |
| `FeeSwapperUpdated(oldFeeSwapper, newFeeSwapper)` | `oldFeeSwapper`, `newFeeSwapper` | Fee swapper changed |

### FeeManager (`FeeManager.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `EltaDeposited(appId, amount, from)` | `appId`, `from` | ELTA received from collector |
| `EpochClosed(appId, epochId, totalDistributed)` | `appId`, `epochId` | Epoch rewards distributed |
| `CallerIncentivePaid(caller, amount, epochId)` | `caller`, `epochId` | Bot caller incentive paid |
| `FeeSplitsUpdated(appStakers, veElta, creator, treasury, referral)` | - | Fee split ratios changed |
| `DepositorUpdated(depositor, allowed)` | `depositor` | Depositor authorization changed |
| `AppCreatorUpdated(appId, creator)` | `appId`, `creator` | App creator updated |
| `TreasurySwapExecuted(eltaIn, usdcOut)` | - | ELTA swapped to USDC for treasury |
| `SwapRouterUpdated(oldRouter, newRouter)` | `oldRouter`, `newRouter` | Swap router changed |

### FeeSwapper (`FeeSwapper.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `Swapped(tokenIn, tokenOut, amountIn, amountOut, router)` | `tokenIn`, `tokenOut`, `router` | Token swap executed |
| `RouterAllowlistUpdated(router, allowed)` | `router` | Router authorization changed |
| `MaxSlippageBpsUpdated(oldBps, newBps)` | - | Max slippage setting changed |
| `FeeManagerUpdated(oldFeeManager, newFeeManager)` | `oldFeeManager`, `newFeeManager` | Fee manager changed |
| `MinSwapThresholdUpdated(oldThreshold, newThreshold)` | - | Min swap threshold changed |

### AppFeeRouter (`AppFeeRouter.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `FeeForwarded(source, payer, grossAmount, fee)` | `source`, `payer` | Fees forwarded to collector |
| `FeeBpsUpdated(oldBps, newBps)` | - | Fee basis points changed |
| `GovernanceTransferred(oldGov, newGov)` | `oldGov`, `newGov` | Governance role transferred |

### TreasuryUSDCVault (`TreasuryUSDCVault.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `TreasuryRevenue(appId, usdcAmount, epochId)` | `appId`, `epochId` | USDC revenue received |
| `Withdrawal(to, amount, caller)` | `to`, `caller` | USDC withdrawn by treasury |
| `TreasuryMultisigUpdated(oldMultisig, newMultisig)` | `oldMultisig`, `newMultisig` | Multisig changed |
| `FeeManagerUpdated(oldFeeManager, newFeeManager)` | `oldFeeManager`, `newFeeManager` | Fee manager changed |

## Governance Events

### ElataGovernor (`ElataGovernor.sol`)
Standard OpenZeppelin Governor events plus:
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `EmergencyProposalCreated(proposalId, description)` | `proposalId` | Emergency proposal created |
| `CustomProposalExecuted(proposalId)` | `proposalId` | Custom proposal executed |

### ProtocolConfig (`ProtocolConfig.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `AppCreationFeeUpdated(oldFee, newFee)` | - | App creation fee changed |
| `AppCreationSeedUpdated(oldSeed, newSeed)` | - | ELTA seed amount changed |
| `BondingCurveTaxUpdated(oldBps, newBps)` | - | Bonding curve tax changed |
| `GraduationTargetUpdated(oldTarget, newTarget)` | - | Graduation threshold changed |
| `LpLockDurationUpdated(oldDuration, newDuration)` | - | LP lock duration changed |
| `ActivationDelayUpdated(oldDelay, newDelay)` | - | Activation delay changed |
| `MaxCurveDurationUpdated(oldDuration, newDuration)` | - | Max curve duration changed |
| `AppTransferTaxUpdated(oldBps, newBps)` | - | Transfer tax changed |
| `MaxAppTransferTaxUpdated(oldMax, newMax)` | - | Max transfer tax changed |
| `FeeSplitsUpdated(appStakers, veElta, creator, treasury, referral)` | - | Fee splits changed |
| `EpochLengthUpdated(oldLength, newLength)` | - | Epoch length changed |
| `MaxSlippageUpdated(oldBps, newBps)` | - | Max slippage changed |
| `RouterAllowlisted(router, allowed)` | `router` | Router allowlist changed |
| `TreasuryUpdated(oldTreasury, newTreasury)` | `oldTreasury`, `newTreasury` | Treasury address changed |
| `AdminTransferred(oldAdmin, newAdmin)` | `oldAdmin`, `newAdmin` | Admin role transferred |
| `MinSwapThresholdUpdated(oldThreshold, newThreshold)` | - | Min swap threshold changed |

## Module Events

### AppModuleFactory (`AppModuleFactory.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `ModulesDeployed(appToken, content721, contentStore)` | `appToken` | Content modules deployed |
| `TreasurySet(treasury)` | - | Treasury set |
| `FeeCollectorSet(feeCollector)` | - | Fee collector set |
| `FeeSet(fee)` | - | Module fee set |
| `DefaultProtocolFeeBpsSet(bps)` | - | Default protocol fee set |

### ContentStore (`ContentStore.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `ContentListed(contentId, uri, price, maxSupply)` | `contentId` | Content item listed for sale |
| `ContentListedWithTimeWindow(...)` | `contentId` | Content listed with time restrictions |
| `ContentPurchased(contentId, buyer, price)` | `contentId`, `buyer` | Content purchased |
| `ContentDeactivated(contentId)` | `contentId` | Content deactivated |
| `ContentReactivated(contentId)` | `contentId` | Content reactivated |
| `ProtocolFeeBpsUpdated(oldBps, newBps)` | - | Protocol fee changed |
| `FeeCollectorUpdated(oldCollector, newCollector)` | - | Fee collector changed |
| `RevenueWithdrawn(to, amount)` | `to` | Creator revenue withdrawn |
| `BurnBpsUpdated(oldBps, newBps)` | - | Burn fee changed |
| `FeatureGateSet(contentId, gateType, minBalance, tokenAddress)` | `contentId` | Feature gate configured |
| `ContentTimeWindowUpdated(contentId, startTime, endTime)` | `contentId` | Time window updated |

### InAppContent721 (`InAppContent721.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `MinterUpdated(oldMinter, newMinter)` | `oldMinter`, `newMinter` | Minter role changed |
| `ContractURIUpdated(oldURI, newURI)` | - | Contract metadata changed |
| `DefaultRoyaltySet(receiver, feeNumerator)` | `receiver` | Default royalty set |
| `TokenRoyaltySet(tokenId, receiver, feeNumerator)` | `tokenId`, `receiver` | Token-specific royalty set |
| `TokenMetadataUpdated(tokenId, uri)` | `tokenId` | Token URI updated |
| `SoulboundSet(tokenId, isSoulbound)` | `tokenId` | Soulbound status set |

### Tournament (`Tournament.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `Entered(user, fee)` | `user` | User entered tournament |
| `Finalized(winnersRoot, netPool, protocolFee, burned)` | - | Tournament finalized |
| `Claimed(user, amount)` | `user` | Winner claimed prize |
| `FeesSet(protocolFeeBps, burnFeeBps)` | - | Fees configured |
| `WindowSet(startTime, endTime)` | - | Tournament window set |
| `EntryFeeSet(entryFee)` | - | Entry fee set |

### TournamentFactory (`TournamentFactory.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `TournamentCreated(tournament, appToken, entryFee, startTime, endTime)` | `tournament`, `appToken` | Tournament deployed |
| `TreasurySet(treasury)` | - | Treasury set |
| `DefaultFeesSet(protocolFeeBps, burnFeeBps)` | - | Default fees set |

### AirdropDistributor (`AirdropDistributor.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `CampaignCreated(campaignId, token, merkleRoot)` | `campaignId`, `token` | Airdrop campaign created |
| `Claimed(campaignId, account, amount)` | `campaignId`, `account` | Tokens claimed |
| `CampaignDeactivated(campaignId)` | `campaignId` | Campaign ended |
| `OperatorUpdated(oldOperator, newOperator)` | `oldOperator`, `newOperator` | Operator changed |
| `AdminUpdated(oldAdmin, newAdmin)` | `oldAdmin`, `newAdmin` | Admin changed |
| `TokensRescued(token, to, amount)` | `token`, `to` | Stuck tokens rescued |

### ReferralRegistry (`ReferralRegistry.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `ReferrerSet(appId, buyer, referrer)` | `appId`, `buyer`, `referrer` | Referral relationship set |
| `RewardAccrued(appId, referrer, buyer, amount)` | `appId`, `referrer`, `buyer` | Referral reward earned |
| `RewardsClaimed(referrer, amount)` | `referrer` | Referrer claimed rewards |
| `ReferralBpsUpdated(oldBps, newBps)` | - | Referral rate changed |
| `AuthorizedCallerUpdated(caller, authorized)` | `caller` | Caller authorization changed |
| `AdminUpdated(oldAdmin, newAdmin)` | `oldAdmin`, `newAdmin` | Admin changed |

## Vesting Events

### AppEcosystemVault (`AppEcosystemVault.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `TokensWithdrawn(token, to, amount)` | `token`, `to` | Tokens withdrawn from vault |
| `AdminUpdated(oldAdmin, newAdmin)` | `oldAdmin`, `newAdmin` | Admin changed |

### AppVestingWallet (`AppVestingWallet.sol`)
| Event | Indexed Fields | Description |
|-------|---------------|-------------|
| `TokensReleased(token, amount)` | `token` | Vested tokens released |
| `BeneficiaryUpdated(oldBeneficiary, newBeneficiary)` | `oldBeneficiary`, `newBeneficiary` | Beneficiary changed |
| `AdminUpdated(oldAdmin, newAdmin)` | `oldAdmin`, `newAdmin` | Admin changed |

## Indexer Recommendations

### High-Priority Events (Real-time)
- `AppCreated` - Track new apps
- `TokensPurchased` - Track trades
- `AppGraduated` - Track graduations
- `VeRewardsClaimed` - Track reward claims
- `Staked`/`Unstaked` - Track staking activity

### Medium-Priority Events (Batch processing)
- `Locked`/`Unlocked` - veELTA position changes
- `EpochClosed` - Epoch transitions
- `ContentPurchased` - Content sales

### Low-Priority Events (Periodic sync)
- Configuration update events
- Admin transfer events
