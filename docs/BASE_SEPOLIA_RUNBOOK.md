# Base Sepolia Runbook (Launch-Ready)

This runbook is the repeatable deployment + verification checklist for the current protocol design:

- Fee policy: app revenue routes **80/20** via `FeeSwapper` (contributors/treasury)
- `LAUNCH_FEE`: **100% treasury**
- No tokenholder yield distribution path
- Premium content: ERC-721 only, with tokenless + token-launched flows

## 1) Preflight

From `elata-protocol/`:

```bash
# Fast safety checks first
FOUNDRY_PROFILE=local forge test --match-path test/integration/FeeSplit80_20.t.sol
FOUNDRY_PROFILE=local forge test --match-path test/fees/FeeSwapper.t.sol
FOUNDRY_PROFILE=local forge test --match-path test/integration/FeePipeline.t.sol
FOUNDRY_PROFILE=local forge test --match-path test/security/economic/FeePipelineAdvanced.t.sol

# Full suite (recommended before broadcast)
FOUNDRY_PROFILE=ci forge test
```

## 2) Environment

Create/update `.env.sepolia` in `elata-protocol/`:

```bash
BASE_SEPOLIA_RPC_URL=...
BASESCAN_API_KEY=...
ADMIN_MSIG=0x...
INITIAL_TREASURY=0x...
```

For Ledger deployment you do **not** need a private key in this file.

## 3) Dry-Run Simulation (No Broadcast)

```bash
forge script script/Deploy.sol:Deploy --rpc-url "$BASE_SEPOLIA_RPC_URL"
```

Confirm simulation succeeds and that the deployed stack includes:

- `AppRegistry`
- `ContributorSplitFactory`
- `FeeSwapper`
- `FeeCollector`
- `ContentStoreFactory`
- `InAppContent721Factory`

## 4) Broadcast (Ledger)

```bash
bash scripts/deploy-sepolia.sh --ledger
```

`deploy-sepolia.sh` sets `ELATA_DEPLOYMENT_TAG` automatically and `Deploy.sol` writes a tagged artifact:

- `deployments/base-sepolia-<YYYYMMDD-HHMM>-<sha>.json`

This avoids relying on `base-sepolia-deployment.json`, which can be overwritten by simulations.

## 5) Post-Broadcast Verification

Run verification against the real tagged artifact:

```bash
bash scripts/verify-sepolia.sh deployments/base-sepolia-<YYYYMMDD-HHMM>-<sha>.json
```

Expected critical checks:

- Contract code exists for core deployed contracts
- `ELTA.totalSupply == 77_000_000e18`
- `FeeSwapper.governance == ElataTimelock`
- `FeeSwapper.defaultTreasuryTakeBps == 2000`
- Router allowlisted in `FeeSwapper`
- `ContentStoreFactory.feeSwapper == FeeSwapper`

## 6) Sync Appstore Addresses

From `elata-appstore/`:

```bash
node scripts/generate-addresses.js
```

The generator now prefers the newest tagged Base Sepolia artifact.

## 7) Manual Smoke Validation (Base Sepolia)

Run these user journeys end-to-end in the appstore against chain `84532`:

1. **Launch wizard**
   - Create tokenless app
   - Launch token from review flow
   - Confirm ownerSafe mismatch warning/gating is enforced
2. **Premium content (tokenless)**
   - Deploy content modules
   - Seed content
   - Buy using `NATIVE`, `ELTA`, `USDC`
3. **Premium content (token-launched)**
   - Attach launched token
   - Buy using `NATIVE`, `ELTA`, `USDC`, `APP`
4. **Trading + fee path**
   - Buy/sell app token
   - Sweep fees if needed
   - Confirm no tokenholder yield path

## 8) On-Chain Spot Checks

Use `cast` against the tagged deployment JSON addresses to confirm economics:

- For app revenue fee kinds, balances move 80/20 to contributor split and treasury
- For paused app, fee routes 100% treasury
- For launch fee kind, fee routes 100% treasury

## 9) Ship Gate

Proceed only when all are true:

- Broadcast successful and tagged artifact stored
- Verification script passes on tagged artifact
- Appstore addresses regenerated from tagged artifact
- Manual smoke flows pass on Base Sepolia
- No unresolved regressions in `FOUNDRY_PROFILE=ci forge test`
