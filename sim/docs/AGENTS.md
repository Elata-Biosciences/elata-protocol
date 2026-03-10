# Agent Architecture Documentation

This document describes the agent system used in the Elata Protocol simulation framework.

## Overview

Agents are autonomous actors that interact with the protocol during simulations. Each agent has specific behaviors and goals, allowing realistic testing of protocol dynamics.

## Base Classes

### BaseProtocolAgent

All agents extend `BaseProtocolAgent`, which provides:

- **Wallet management**: Each agent gets a unique wallet address
- **Balance tracking**: ELTA, veELTA, and app token balances
- **World state access**: Query protocol state
- **Action creation helpers**: Build actions for execution
- **Risk/trade calculation**: Configurable risk parameters

### Common Parameters

All agents accept these base parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `riskTolerance` | number | 0.5 | Risk tolerance (0-1, higher = more aggressive) |
| `maxTradePercent` | number | 0.1 | Max percentage of balance per trade |
| `minEltaReserve` | bigint | 0n | Minimum ELTA to keep in reserve |

## Agent Types

### Trading Agents

#### BasicUserAgent
Standard user behavior with configurable buy/sell probabilities.

Parameters:
- `buyProbability`: Chance to buy each tick (default: 0.3)
- `sellProbability`: Chance to sell each tick (default: 0.2)

#### WhaleUserAgent
Large trader with significant position sizes.

Parameters:
- `minTradeSize`: Minimum trade size
- `maxTradeSize`: Maximum trade size
- `buyProbability`: Buy chance
- `sellProbability`: Sell chance

#### CautiousUserAgent
Risk-averse user who sells on price drops.

Parameters:
- `riskTolerance`: Risk tolerance (usually low)
- `sellThreshold`: Price drop % to trigger sell

### Developer Agents

#### DeveloperAgent
Creates new apps on the protocol.

Parameters:
- `maxApps`: Maximum apps to create
- `launchProbability`: Chance to create per tick

#### SerialDeveloperAgent
Creates many apps quickly with less focus on quality.

#### QualityDeveloperAgent
Creates fewer, higher-quality apps with more engagement.

### Staking Agents

#### StakerAgent
Focuses on veELTA staking for voting power.

Parameters:
- `minLockAmount`: Minimum ELTA to lock
- `lockDurationDays`: Lock duration (730 max for max boost)
- `claimProbability`: Reward claim probability
- `compoundProbability`: Compounding probability

#### AppStakerAgent
Stakes app tokens in app-specific vaults.

### Reward Agents

#### RewardHunterAgent
Aggressively claims all available rewards.

Parameters:
- `claimAggressiveness`: How often to claim (0-1)
- `compoundRewards`: Whether to compound
- `minCompoundAmount`: Minimum amount to compound

### Governance Agents

#### GovernorAgent
Creates and manages governance proposals.

Parameters:
- `minVotingPower`: Required veELTA
- `proposeProbability`: Proposal creation chance
- `voteProbability`: Voting chance
- `proposalCooldown`: Ticks between proposals

#### VoterAgent
Votes on governance proposals without creating them.

Parameters:
- `minVotingPower`: Required veELTA
- `voteProbability`: Voting chance
- `preferSupportive`: Vote FOR preference

### Fee Agents

#### FeeKeeperAgent
Sweeps fees and closes fee epochs.

Parameters:
- `minFeeThreshold`: Minimum fees to sweep
- `sweepProbability`: Sweep chance
- `closeProbability`: Epoch close chance

### Tournament/Content Agents

#### TournamentOrganizerAgent
Creates and manages tournaments.

#### CompetitorAgent
Enters tournaments and competes.

#### ContentCreatorAgent
Lists content in app content stores.

#### CollectorAgent
Purchases content NFTs.

### Specialized Agents

#### ArbitragerAgent
Exploits price differences across apps.

#### ReferrerAgent
Builds referral networks.

#### AirdropHunterAgent
Claims eligible airdrops.

#### VestingBeneficiaryAgent
Releases vested tokens.

### Adversarial Agents

#### ManipulatorAgent
Attempts price manipulation.

Parameters:
- `aggressiveness`: How aggressive (0-1)
- `preferredStrategy`: 'pump_dump', 'accumulate', or 'front_run'
- `maxPositionPercent`: Max position size

#### SpammerAgent
Generates high transaction volumes.

Parameters:
- `spamType`: 'micro_trades' or 'app_creation'
- `minTradeSize`: Minimum trade size

## Agent Lifecycle

1. **initialize(ctx)**: Called once at simulation start
   - Register with pack
   - Get wallet address
   - Fetch initial balances

2. **step(ctx)**: Called every tick
   - Evaluate world state
   - Decide on action (or return null)
   - Return single action

3. **finalize(ctx)**: Called at simulation end
   - Cleanup resources
   - Report final state

## Helper Methods

### Balance Helpers
- `getEltaBalance()`: Get cached ELTA balance
- `getVeEltaBalance()`: Get cached veELTA balance
- `getAppTokenBalance(appId)`: Get app token balance
- `hasEnoughElta(amount)`: Check if balance is sufficient
- `updateBalances()`: Refresh all cached balances

### State Helpers
- `getWorldState()`: Get current world state
- `getAppState(appId)`: Get specific app state
- `getAllApps()`: Get all apps
- `getAppCount()`: Get number of apps

### Governance Helpers
- `hasVotingPower(minPower)`: Check voting power
- `getProposalThreshold()`: Get proposal threshold
- `getProposalState(proposalId)`: Query on-chain state
- `hasVotedOnProposal(proposalId)`: Check if voted

### Rewards Helpers
- `hasClaimableVeEltaRewards()`: Check for claimable veELTA rewards
- `hasClaimableAppRewards(appId)`: Check for app staking rewards
- `getStakedBalance(appId)`: Get staked balance

### Action Helpers
- `createAction(name, payload, tick)`: Create an action
- `shouldAct(ctx, probability)`: Random probability check
- `calculateTradeAmount(available, ctx)`: Calculate trade size
- `formatElta(amount)`: Format amount for logging
