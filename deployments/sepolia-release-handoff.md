## Sepolia Release Handoff

Deployment network: Ethereum Sepolia (`11155111`)  
Canonical artifact: `deployments/sepolia-20260226-2046-1871e41.json`  
Latest broadcast bundle: `broadcast/Deploy.sol/11155111/run-latest.json`

### Verification Status

- Post-deploy verification script succeeded:
  - `SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com bash scripts/verify-sepolia.sh deployments/sepolia-20260226-2046-1871e41.json`
- Core checks passed:
  - bytecode exists at all deployed addresses
  - `ELTA.totalSupply == 77_000_000e18`
  - `FeeSwapper.governance == ElataTimelock`
  - `FeeSwapper.defaultTreasuryTakeBps == 2000`
  - `FeeSwapper` router allowlist includes Sepolia Uniswap V2 router
  - `ContentStoreFactory.feeSwapper == FeeSwapper`

### Smoke Checks (Read + Launch-Path Wiring)

Read-only checks on Sepolia succeeded:

- `AppFactory.paused() == false`
- `AppFactory.creationFee() == 10e18`
- `AppFactory` wiring is set:
  - `appRegistry == 0x5d3677d30fa585497863A4fEA80FCcCC0162cFda`
  - `feeCollector == 0x0584a9894B44939E77330bEa6720BAB6FA263862`
  - `protocolConfig == 0xDe5090F5269786671a9bff0C91A538Af34069a95`
  - `contributorSplitFactory == 0x5f4879607a28626f062f758e77D4234654BCD6A0`
  - `feeSwapper == 0x909e0fF2c22554E98de83BB495B95765F4C4eD11`
- `AppFactory` default admin role is held by multisig `0xC50e39B8e22710790939f02Ad77CEb99c1cC7DF4`

This provides a safe lifecycle sanity baseline for app creation path dependencies without broadcast writes.

### Address Set

See: `deployments/sepolia-address-table.md`

### Explorer Links

- Base deployment set starts from ELTA: `https://sepolia.etherscan.io/address/0x2AEb03A678A1e1E99a2AeEb4CeFCD0263A2D3587`
- FeeSwapper: `https://sepolia.etherscan.io/address/0x909e0fF2c22554E98de83BB495B95765F4C4eD11`
- ProtocolConfig: `https://sepolia.etherscan.io/address/0xDe5090F5269786671a9bff0C91A538Af34069a95`

### Downstream Env Sync

- `scripts/update-vercel-envs.sh` now consumes Sepolia artifacts and emits Sepolia env keys.
- App consumers updated to resolve `11155111` addresses from generated config and `*_SEPOLIA` env vars.

### Known Non-Blocking CI Lanes (This Cycle)

- Simulation CI temporarily deferred from `vNext`.
- Code quality and gas report are set non-blocking for deployment-cycle velocity.

### Rollback / Mitigation Playbook

If unexpected behavior is observed:

1. **Pause new launches** using `AppFactory.setPaused(true)` via multisig admin.
2. **Restrict fee routes** by governance actions on `FeeSwapper` allowlist/treasury settings.
3. **Halt or tune protocol parameters** through `ProtocolConfig` and governance timelock flow.
4. **Operational comms**: publish impacted contract(s), tx links, and mitigation transaction hashes.

Primary control owner: multisig `0xC50e39B8e22710790939f02Ad77CEb99c1cC7DF4`.
