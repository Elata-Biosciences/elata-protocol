# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| vNext   | Development (not audited) |
| main    | Stable (pending audit) |

## Reporting a Vulnerability

**Do not open a public issue.**

Email: security@elata.bio

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Affected contracts
- Any suggested fixes

## Response Timeline

- Initial acknowledgment: 48 hours
- Status update: 7 days
- Resolution: Severity-dependent

## Scope

All contracts in `src/`:

**Token Layer**
- VeELTA — Vote-escrowed staking
- ElataPoints — Non-transferable reputation

**Governance**
- ElataGovernor — On-chain governance
- ElataTimelock — Execution delays

**Rewards**
- RewardsDistributor — Protocol fee distribution
- AppRewardsDistributor — Per-app rewards

**App Ecosystem**
- AppFactory — App token launches
- AppBondingCurve — Price discovery
- AppToken — App token implementation
- AppStakingVault — Per-app staking
- ContentStore — Digital content sales
- InAppContent721 — ERC-721 content
- Tournament — Competitive events

**Fees**
- AppFeeRouter — Fee routing
- FeeManager — Fee conversion
- FeeCollector — Fee collection
- FeeSwapper — Token swaps
- TreasuryUSDCVault — Treasury management

**Modules**
- AirdropDistributor — Token airdrops
- ReferralRegistry — Referral tracking

**Vesting**
- AppVestingWallet — Token vesting
- AppEcosystemVault — Ecosystem token custody

## Out of Scope

- ELTA token contract (see [ELTA repository](../ELTA/SECURITY.md))
- Frontend applications
- Off-chain infrastructure

## Audit Status

External audit pending before mainnet deployment.

## Bug Bounty

Contact us for information about our bug bounty program.
